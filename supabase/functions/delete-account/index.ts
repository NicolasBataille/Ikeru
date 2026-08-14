// supabase/functions/delete-account/index.ts
//
// Deno Edge Function: erases every server-side row belonging to the calling
// anonymous identity, then deletes the `auth.users` row itself.
//
// WHY THIS HAS TO BE AN EDGE FUNCTION (not a client-side call):
// the app only ever ships the publishable ("anon") key — see
// `IkeruCore/Sources/Services/Sync/SyncJSON.swift`'s `SupabaseConfig` doc
// comment. That key can only do what Row Level Security lets `auth.uid()`
// do, and RLS policies grant a user DML on their own rows, never DDL on
// `auth.users`. Deleting the `auth.users` row requires the `service_role`
// key, which must never reach a client device (repo is PUBLIC — see
// CLAUDE.md "Sécurité (repo public)"). So this function is the only place
// that key may be read, and it reads it exclusively from the Edge Function
// runtime's environment (`SUPABASE_SERVICE_ROLE_KEY`, auto-injected by the
// Supabase platform for every deployed function) — never hardcoded, never
// logged.
//
// Sync tables covered here are exactly the ones `SyncPayloadBuilder.swift`
// pushes to, PLUS `companion_chat_messages` (the task's item 4 wants a
// TOTAL erasure of anything that could exist under this user_id server-side,
// even though the app itself currently never pushes rows into that table —
// see `SyncPayloadBuilder.swift`'s closing comment. If a future lot starts
// pushing chat history, this function already covers it with no changes
// needed here).
//
// DELETION ORDER: verified live against project `aiayzlarixlogcoyswna` via
// `pg_constraint` (2026-08-14) that every one of these 8 tables' `user_id`
// column is `REFERENCES auth.users(id) ON DELETE CASCADE`. That means
// deleting the `auth.users` row alone would already cascade-wipe all 8
// tables — the explicit per-table deletes below are NOT load-bearing for
// correctness. They exist so this function can (a) report an honest
// per-table row count in its response instead of a black-box "trust the
// cascade", and (b) keep working exactly the same way if that CASCADE rule
// is ever changed by a future migration. `profile_id` / `card_id` /
// `entry_id` are plain UUID columns with NO enforced foreign-key constraint
// in the live schema (also verified via `pg_constraint`) — so there is no
// database-level ordering requirement between the 8 tables themselves.
// Deletion below still runs child-shaped tables (the ones that reference a
// card/entry/profile conceptually) before `profiles`, purely as defensive
// practice against a future migration that DOES add those FKs.
const DELETE_ORDER = [
  "review_logs",
  "vocabulary_encounters",
  "exercise_outcome_logs",
  "companion_chat_messages",
  "cards",
  "rpg_states",
  "vocabulary_entries",
  "profiles",
] as const;

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "missing_authorization_header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    // Never happens on a real deploy (Supabase injects all three for every
    // Edge Function) — this only fires in a broken local/dev invocation, and
    // failing loudly beats silently no-op'ing a delete-account request.
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  // Both createClient calls below need the module import; done here (not at
  // top-level `import`) so the misconfiguration check above can return
  // before any network client is constructed — irrelevant to correctness,
  // just avoids a pointless client object on the 500 path.
  const { createClient } = await import(
    "https://esm.sh/@supabase/supabase-js@2"
  );

  // ---------------------------------------------------------------------
  // SECURITY CORE OF THIS FILE: identify the caller from THEIR OWN JWT,
  // never from anything in the request body. A client-supplied user_id in
  // the body would let any caller who can reach this endpoint delete any
  // OTHER user's data just by naming their id — there is no way to validate
  // a bare UUID string as "belongs to whoever is asking" without the JWT
  // check below. `auth.getUser()` on a client built with the CALLER's
  // bearer token is what actually proves "this request is authenticated as
  // this specific user" — GoTrue verifies the JWT signature and expiry
  // server-side; we never decode/trust it ourselves.
  // ---------------------------------------------------------------------
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const {
    data: { user },
    error: getUserError,
  } = await callerClient.auth.getUser();

  if (getUserError || !user) {
    return jsonResponse({ error: "invalid_or_expired_token" }, 401);
  }

  const userID = user.id;

  // Constructed ONLY after the caller's identity is verified above — this
  // client holds the `service_role` key, which bypasses Row Level Security
  // entirely. Every query issued through it below MUST carry an explicit
  // `.eq("user_id", userID)` filter; service_role does not get that
  // narrowing for free the way an RLS-scoped anon/authenticated client
  // would. Forgetting that filter on any single table would wipe that
  // table for every user on the project, not just this one — this is the
  // second half of this file's security core, paired with the identity
  // check above.
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const deletedCounts: Record<string, number> = {};

  for (const table of DELETE_ORDER) {
    const { error, count } = await adminClient
      .from(table)
      .delete({ count: "exact" })
      .eq("user_id", userID);

    if (error) {
      // Fail loud, name the table, stop here. Every delete above this
      // point already committed (each `.delete()` call is its own
      // transaction) and is idempotent to retry — a retried call re-deletes
      // an already-empty table harmlessly and moves on to the table that
      // failed. Never return 200 on a partial deletion.
      return jsonResponse(
        {
          error: "delete_failed",
          table,
          detail: error.message,
          deletedCounts,
        },
        500,
      );
    }

    deletedCounts[table] = count ?? 0;
  }

  // Deleting the `auth.users` row last: every table above already carries
  // `ON DELETE CASCADE` on `user_id` (verified, see the top-of-file
  // comment), so this call alone would have been sufficient for data
  // removal — it is NOT redundant, though, because it is what actually
  // invalidates the caller's session and frees the identity. Doing it last
  // means a failure here still leaves the per-table data genuinely gone
  // (reported in `deletedCounts`), which is the outcome that matters most
  // for a GDPR erasure request even if the now-orphaned empty auth user
  // needs a manual follow-up.
  const { error: deleteUserError } = await adminClient.auth.admin.deleteUser(
    userID,
  );

  if (deleteUserError) {
    return jsonResponse(
      {
        error: "auth_user_delete_failed",
        detail: deleteUserError.message,
        deletedCounts,
      },
      500,
    );
  }

  return jsonResponse({ deletedCounts, userID }, 200);
});
