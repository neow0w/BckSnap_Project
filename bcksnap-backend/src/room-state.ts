
import { DurableObject } from "cloudflare:workers";
import { RoomServiceClient } from "livekit-server-sdk";

interface Env {
  LIVEKIT_URL: string;
  LIVEKIT_API_KEY: string;
  LIVEKIT_API_SECRET: string;
}

interface RoomUpdate {
  roomName: string;
  eventId: string;
}

interface RoomSetup {
  roomName: string;
}

const INACTIVITY_PERIOD = 30 * 60 * 1000;
const MAX_STORED_EVENTS = 100;

export class RoomState extends DurableObject<Env> {
  private roomService: RoomServiceClient;

  // Ensures that updates and alarms are processed one at a time.
  private operationQueue: Promise<void> = Promise.resolve();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);

    this.roomService = new RoomServiceClient(
      env.LIVEKIT_URL,
      env.LIVEKIT_API_KEY,
      env.LIVEKIT_API_SECRET
    );
  }

  private async runExclusive<T>(
    operation: () => Promise<T>
  ): Promise<T> {
    const previous = this.operationQueue;

    let release!: () => void;

    this.operationQueue = new Promise<void>((resolve) => {
      release = resolve;
    });

    await previous;

    try {
      return await operation();
    } finally {
      release();
    }
  }

  async fetch(request: Request): Promise<Response> {
    if (
      request.method === "GET" &&
      new URL(request.url).pathname === "/status"
    ) {
      const roomClosed =
        (await this.ctx.storage.get<boolean>("roomClosed")) ?? false;

      const instantMeetingEnabled =
        (await this.ctx.storage.get<boolean>("instantMeetingEnabled")) ?? false;

      return Response.json({
        roomClosed,
        instantMeetingEnabled,
      });
    }


    if (
      request.method === "POST" &&
      new URL(request.url).pathname === "/ensure-room"
    ) {
      let setup: RoomSetup;

      try {
        setup = await request.json<RoomSetup>();
      } catch {
        return Response.json(
          { error: "Invalid room setup" },
          { status: 400 }
        );
      }

      if (
        typeof setup.roomName !== "string" ||
        !setup.roomName.trim()
      ) {
        return Response.json(
          { error: "Invalid room name" },
          { status: 400 }
        );
      }

      return this.runExclusive(async () => {
        const roomClosed =
          (await this.ctx.storage.get<boolean>("roomClosed")) ?? false;

        const existingRoomName =
          await this.ctx.storage.get<string>("roomName");

        if (
          existingRoomName &&
          existingRoomName !== setup.roomName
        ) {
          return Response.json(
            { error: "Room name mismatch" },
            { status: 409 }
          );
        }

        let existingRooms =
          await this.roomService.listRooms([setup.roomName]);

        if (roomClosed) {
          // Recreate the room after the previous meeting was ended.
          if (existingRooms.length > 0) {
            await this.roomService.deleteRoom(setup.roomName);
          }

          await this.roomService.createRoom({
            name: setup.roomName,
            maxParticipants: 2,
            emptyTimeout: 1800,
          });

          // Reset the previous meeting's state.
          await this.ctx.storage.put("roomClosed", false);
          await this.ctx.storage.put("instantMeetingEnabled", false);

          await this.ctx.storage.delete("participantCount");
          await this.ctx.storage.delete("processedEvents");
          await this.ctx.storage.delete("closeDeadline");
          await this.ctx.storage.deleteAlarm();

          existingRooms = [];
        } else if (existingRooms.length === 0) {
          // Create the room if it does not exist yet.
          await this.roomService.createRoom({
            name: setup.roomName,
            maxParticipants: 2,
            emptyTimeout: 1800,
          });
        }

        await this.ctx.storage.put("roomName", setup.roomName);

        return Response.json({
          success: true,
          roomName: setup.roomName,
          created: existingRooms.length === 0,
          reopened: roomClosed,
        });
      });
    }


    if (
      request.method === "POST" &&
      new URL(request.url).pathname === "/enable-instant"
    ) {
      let data: RoomSetup;

      try {
        data = await request.json<RoomSetup>();
      } catch {
        return Response.json(
          { error: "Invalid instant meeting request." },
          { status: 400 }
        );
      }

      if (
        typeof data.roomName !== "string" ||
        !data.roomName.trim()
      ) {
        return Response.json(
          { error: "Invalid room name." },
          { status: 400 }
        );
      }

      return this.runExclusive(async () => {
        const roomClosed =
          (await this.ctx.storage.get<boolean>("roomClosed")) ?? false;

        if (roomClosed) {
          return Response.json(
            { error: "This consultation room has already been closed." },
            { status: 410 }
          );
        }

        const existingRoomName =
          await this.ctx.storage.get<string>("roomName");

        if (
          !existingRoomName ||
          existingRoomName !== data.roomName
        ) {
          return Response.json(
            { error: "Consultation room not found." },
            { status: 404 }
          );
        }

        await this.ctx.storage.put("instantMeetingEnabled", true);

        return Response.json({
          success: true,
          instantMeetingEnabled: true,
        });
      });
    }

    if (request.method === "POST" && new URL(request.url).pathname === "/end-room") {
      let data: RoomSetup;

      try {
        data = await request.json<RoomSetup>();
      } catch {
        return Response.json(
          { error: "Invalid room closure request" },
          { status: 400 }
        );
      }
      if (typeof data.roomName !== "string" || !data.roomName.trim()) {
        return Response.json(
          { error: "Invalid room name" },
          { status: 400 }
        );
      }
      return this.runExclusive(async () => {
        const roomClosed = (await this.ctx.storage.get<boolean>("roomClosed")) ?? false;

        if (roomClosed) {
          return Response.json({
            success: true,
            alreadyClosed: true,
          });
        }

        const existingRoomName = await this.ctx.storage.get<string>("roomName");

        if (!existingRoomName || existingRoomName !== data.roomName) {
          return Response.json(
            { error: "Room name mismatch or room not found" },
            { status: 409 }
          );
        }
        await this.roomService.deleteRoom(data.roomName);

        await this.ctx.storage.put("roomClosed", true);
        await this.ctx.storage.put("instantMeetingEnabled", false);
        await this.ctx.storage.put("participantCount", 0);

        await this.ctx.storage.delete("closeDeadline");
        await this.ctx.storage.deleteAlarm();

        return Response.json({
          success: true,
          alreadyClosed: false,
        });
      });
    }

    if (request.method !== "POST") {
      return new Response("Method Not Allowed", { status: 405 });
    }

    let data: RoomUpdate;

    try {
      data = await request.json<RoomUpdate>();
    } catch {
      return Response.json(
        { error: "Invalid request body" },
        { status: 400 }
      );
    }

    if (
      typeof data.roomName !== "string" ||
      !data.roomName.trim() ||
      typeof data.eventId !== "string" ||
      !data.eventId.trim()
    ) {
      return Response.json(
        { error: "Invalid room update" },
        { status: 400 }
      );
    }

    return this.runExclusive(async () => {
      const roomClosed =
        (await this.ctx.storage.get<boolean>("roomClosed")) ?? false;

      if (roomClosed) {
        return Response.json(
          { error: "Room already closed" },
          { status: 409 }
        );
      }

      const existingRoom =
        await this.ctx.storage.get<string>("roomName");

      if (existingRoom && existingRoom !== data.roomName) {
        return Response.json(
          { error: "Room name mismatch" },
          { status: 409 }
        );
      }

      // Ignore webhook events already processed.
      const processedEvents =
        (await this.ctx.storage.get<string[]>("processedEvents")) ?? [];

      if (processedEvents.includes(data.eventId)) {
        return Response.json({
          success: true,
          duplicate: true,
        });
      }

      // Never trust participant snapshots supplied by the webhook.
      // Query the current participant list directly from LiveKit.
      const participants =
        await this.roomService.listParticipants(data.roomName);

      const participantCount = new Set(
        participants.map((participant) => participant.identity)
      ).size;

      const previousCount =
        await this.ctx.storage.get<number>("participantCount");

      await this.ctx.storage.put("roomName", data.roomName);
      await this.ctx.storage.put("participantCount", participantCount);

      if (participantCount >= 2) {
        // Both participants are present: cancel inactivity countdown.
        await this.ctx.storage.delete("closeDeadline");
        await this.ctx.storage.deleteAlarm();
      } else {
        const shouldStartCountdown =
          (previousCount === undefined && participantCount === 1) ||
          (previousCount === 0 && participantCount === 1) ||
          (previousCount !== undefined && previousCount >= 2);

        const existingDeadline =
          await this.ctx.storage.get<number>("closeDeadline");

        if (shouldStartCountdown && existingDeadline === undefined) {
          const deadline = Date.now() + INACTIVITY_PERIOD;

          await this.ctx.storage.put("closeDeadline", deadline);
          await this.ctx.storage.setAlarm(deadline);
        }
      }

      // Keep a bounded history of processed webhook event IDs.
      const updatedEvents = [
        ...processedEvents,
        data.eventId,
      ].slice(-MAX_STORED_EVENTS);

      await this.ctx.storage.put("processedEvents", updatedEvents);

      const closeDeadline =
        await this.ctx.storage.get<number>("closeDeadline");

      return Response.json({
        success: true,
        participantCount,
        countdownActive: closeDeadline !== undefined,
        closeDeadline: closeDeadline ?? null,
      });
    });
  }

  async alarm(): Promise<void> {
    await this.runExclusive(async () => {
      const deadline =
        await this.ctx.storage.get<number>("closeDeadline");

      const roomName =
        await this.ctx.storage.get<string>("roomName");

      if (deadline === undefined || !roomName) {
        return;
      }

      if (Date.now() < deadline) {
        await this.ctx.storage.setAlarm(deadline);
        return;
      }

      // Check LiveKit again before closing the room.
      const participants =
        await this.roomService.listParticipants(roomName);

      const participantCount = new Set(
        participants.map((participant) => participant.identity)
      ).size;

      await this.ctx.storage.put("participantCount", participantCount);

      if (participantCount >= 2) {
        // Two participants are present: keep the room open.
        await this.ctx.storage.delete("closeDeadline");
        await this.ctx.storage.deleteAlarm();
        return;
      }

      // Zero or one participant remains: close the room.
      await this.roomService.deleteRoom(roomName);

      await this.ctx.storage.put("roomClosed", true);
      await this.ctx.storage.delete("closeDeadline");
      await this.ctx.storage.deleteAlarm();
    });
  }
}
