
import { DurableObject } from "cloudflare:workers";

interface ProfileSession {
  sessionId: string;
  profileId: string;
  clinicId: string;
  role: string;
  expiresAt: number;
}

export class ProfileSessions extends DurableObject {
  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return Response.json(
        { error: "Method not allowed." },
        { status: 405 }
      );
    }

    let data: Partial<ProfileSession>;

    try {
      data = await request.json<Partial<ProfileSession>>();
    } catch {
      return Response.json(
        { error: "Invalid request body." },
        { status: 400 }
      );
    }

    if (url.pathname === "/activate") {
      return this.activate(data);
    }

    if (url.pathname === "/validate") {
      return this.validate(data);
    }

    if (url.pathname === "/revoke") {
      return this.revoke(data);
    }

    return Response.json(
      { error: "Not found." },
      { status: 404 }
    );
  }

  private async activate(
    data: Partial<ProfileSession>
    ): Promise<Response> {
        if (
            typeof data.sessionId !== "string" ||
            !data.sessionId ||
            typeof data.profileId !== "string" ||
            !data.profileId ||
            typeof data.clinicId !== "string" ||
            !data.clinicId ||
            (data.role !== "doctor" && data.role !== "receptionist" && data.role !== "pt") ||
            typeof data.expiresAt !== "number" ||
            !Number.isFinite(data.expiresAt) ||
            data.expiresAt <= Date.now() ||
            data.expiresAt > Date.now() + 8 * 60 * 60 * 1000 + 60000
        ) {
            return Response.json(
                { error: "Invalid profile session." },
                { status: 400 }
            );
        }

        const session: ProfileSession = {
            sessionId: data.sessionId,
            profileId: data.profileId,
            clinicId: data.clinicId,
            role: data.role,
            expiresAt: data.expiresAt,
        };

        await this.ctx.storage.put("activeSession", session);

        return Response.json({ success: true });
    }
  
  private async validate(
    data: Partial<ProfileSession>
    ): Promise<Response> {
        const activeSession =
            await this.ctx.storage.get<ProfileSession>("activeSession");

        if (
            !activeSession ||
            typeof data.sessionId !== "string" ||
            typeof data.profileId !== "string" ||
            typeof data.clinicId !== "string" ||
            (data.role !== "doctor" && data.role !== "receptionist" && data.role !== "pt") ||
            activeSession.sessionId !== data.sessionId ||
            activeSession.profileId !== data.profileId ||
            activeSession.clinicId !== data.clinicId ||
            activeSession.role !== data.role ||
            activeSession.expiresAt <= Date.now()
        ) {
            return Response.json(
            { active: false },
            { status: 401 }
            );
        }

        return Response.json({ active: true });
    }

    private async revoke(
        data: Partial<ProfileSession>
        ): Promise<Response> {
            if (
                typeof data.sessionId !== "string" ||
                !data.sessionId
            ) {
                return Response.json(
                { error: "Invalid session ID." },
                { status: 400 }
                );
            }

            const activeSession =
                await this.ctx.storage.get<ProfileSession>("activeSession");

            if (
                activeSession &&
                data.sessionId === activeSession.sessionId
            ) {
                await this.ctx.storage.delete("activeSession");
            }

            return Response.json({ success: true });
        }
}
