import Foundation

/// The OpenCode plugin Wallflower drops into `~/.config/opencode/plugins/wallflower.js`. It runs
/// inside OpenCode (1.x plugin API), so it needs no helper: it writes the session files itself, with
/// OpenCode's own pid, from the event bus. It keeps only ids, the status and the project folder; no
/// message, prompt or tool data is ever read into it.
enum OpenCodePlugin {
    static func source(sessionsFolder: URL) -> String {
        let folder = JSONLiteral.string(sessionsFolder.path).render(indent: "", unit: "", compact: true)
        return """
        // Wallflower: shows OpenCode sessions as faces at the edge of the screen.
        // Written by Wallflower (Settings > Agents). Disconnecting there deletes this file.
        // It writes one small status file per session into Wallflower's sessions folder: the
        // session id, working / waiting / done, OpenCode's process id and the project folder.
        // Nothing else: no prompts, replies or tool data.
        import fs from "node:fs";
        import path from "node:path";

        const SESSIONS = \(folder);
        const children = new Set();
        const known = new Map();

        function fileId(sessionID) {
          const safe = String(sessionID).replace(/[^A-Za-z0-9._-]/g, "-").slice(0, 118);
          return safe ? "opencode-" + safe : null;
        }

        function write(sessionID, directory, status, waitingFor) {
          try {
            if (!sessionID || children.has(sessionID)) return;
            if (!fs.existsSync(path.dirname(SESSIONS))) return;
            fs.mkdirSync(SESSIONS, { recursive: true });
            const id = fileId(sessionID);
            if (!id) return;
            const now = Date.now();
            const last = known.get(sessionID);
            const state = last ?? { startedAt: now, status: null, waitingFor: null, since: now };
            if (status === null) {
              if (last) return;
              status = "idle";
            }
            const waiting = status === "waiting" ? waitingFor : null;
            if (state.status !== status || state.waitingFor !== waiting) state.since = now;
            state.status = status;
            state.waitingFor = waiting;
            known.set(sessionID, state);
            const record = { id, tool: "opencode" };
            if (directory) record.cwd = directory;
            record.status = status;
            if (waiting) record.waitingFor = waiting;
            record.pid = process.pid;
            record.startedAt = state.startedAt;
            record.updatedAt = now;
            record.statusUpdatedAt = state.since;
            const target = path.join(SESSIONS, id + ".json");
            const temp = path.join(SESSIONS, "." + id + ".json.tmp." + process.pid);
            fs.writeFileSync(temp, JSON.stringify(record, null, 2) + "\\n");
            fs.renameSync(temp, target);
          } catch {}
        }

        function remove(sessionID) {
          try {
            known.delete(sessionID);
            const id = fileId(sessionID);
            if (id) fs.rmSync(path.join(SESSIONS, id + ".json"), { force: true });
          } catch {}
        }

        export const WallflowerPlugin = async ({ directory }) => ({
          event: async ({ event }) => {
            try {
              const p = event?.properties ?? {};
              switch (event?.type) {
                case "session.created": {
                  const info = p.info ?? {};
                  if (info.parentID) { children.add(info.id); return; }
                  write(info.id, directory, null);
                  return;
                }
                case "session.status": {
                  const type = p.status?.type;
                  if (type === "busy" || type === "retry") write(p.sessionID, directory, "busy");
                  else if (type === "idle") write(p.sessionID, directory, "idle");
                  return;
                }
                case "session.idle": write(p.sessionID, directory, "idle"); return;
                case "session.error": if (p.sessionID) write(p.sessionID, directory, "idle"); return;
                case "permission.asked":
                case "permission.updated": write(p.sessionID, directory, "waiting", "permission"); return;
                case "permission.replied": write(p.sessionID, directory, "busy"); return;
                case "question.asked": write(p.sessionID, directory, "waiting", "question"); return;
                case "question.replied":
                case "question.rejected": write(p.sessionID, directory, "busy"); return;
                case "session.deleted": remove(p.info?.id ?? p.sessionID); return;
              }
            } catch {}
          },
        });

        """
    }
}
