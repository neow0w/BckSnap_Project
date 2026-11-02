import { createRemoteJWKSet, jwtVerify } from "jose";
import { AccessToken, WebhookReceiver } from "livekit-server-sdk";

export { RoomState } from "./room-state";

interface Env {
  ROOM_STATE: DurableObjectNamespace;
  LIVEKIT_URL: string;
  LIVEKIT_API_KEY: string;
  LIVEKIT_API_SECRET: string;
}

const FIREBASE_PROJECT_ID = "bcksnap-3f858";

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
  )
);

const APPOINTMENT_PREFIX = "bcksnap_appointment_";
const JOIN_WINDOW_MINUTES = 15;

export default {
  async fetch(
    request: Request,
    env: Env
  ): Promise<Response> {
    const url = new URL(request.url);

    if (
      request.method === "POST" &&
      url.pathname === "/api/consultation/token"
    ) {
      return handleConsultationToken(request, env);
    }

	if (
      request.method === "POST" &&
      url.pathname === "/api/consultation/end"
    ) {
      return handleConsultationEnd(request, env);
    }

	if (
		request.method === "POST" &&
		url.pathname === "/api/livekit/webhook"
	) {
		return handleLiveKitWebhook(request, env);
	}

    return Response.json(
      { error: "Not found" },
      { status: 404 }
    );
  },
} satisfies ExportedHandler<Env>;

async function handleConsultationToken(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    const authorization =
      request.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    const firebaseToken = authorization.substring(7);

    // Verify the Firebase ID token.
    const { payload } = await jwtVerify(
      firebaseToken,
      FIREBASE_JWKS,
      {
        issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
        audience: FIREBASE_PROJECT_ID,
        algorithms: ["RS256"],
      }
    );

    const uid = payload.sub;

    if (!uid) {
      return Response.json(
        { error: "Invalid user identity." },
        { status: 401 }
      );
    }

    const body = await request.json() as {
      appointmentId?: string;
    };

    const appointmentId = body.appointmentId;

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "Invalid appointment ID." },
        { status: 400 }
      );
    }

    // Retrieve the appointment using the caller's Firebase token.
    const appointment = await getFirestoreDocument(
      `appointments/${appointmentId}`,
      firebaseToken
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const fields = appointment.fields ?? {};

    const patientId = fields.userId?.stringValue;
    const doctorId = fields.doctorId?.stringValue;
    const status = fields.status?.stringValue;
    const mode = fields.mode?.stringValue;
    const scheduledAt = fields.scheduledAt?.timestampValue;
    const isDemo = fields.isDemo?.booleanValue ?? false;

    if (
      status !== "approved" ||
      mode !== "online" ||
      isDemo
    ) {
      return Response.json(
        { error: "This appointment is not eligible for an online consultation." },
        { status: 403 }
      );
    }

    if (!scheduledAt) {
      return Response.json(
        { error: "Appointment schedule is unavailable." },
        { status: 400 }
      );
    }

    const scheduledTime = new Date(scheduledAt).getTime();
    const earliestJoinTime =
      scheduledTime - JOIN_WINDOW_MINUTES * 60 * 1000;

    if (
      !Number.isFinite(scheduledTime) ||
      Date.now() < earliestJoinTime
    ) {
      return Response.json(
        { error: "The consultation room is not open yet." },
        { status: 403 }
      );
    }

    // Verify whether the caller is the patient or assigned doctor.
    let participantName = "Consultation Participant";

    if (uid === patientId) {
      const user = await getFirestoreDocument(
        `users/${uid}`,
        firebaseToken
      );

      const role = user?.fields?.role?.stringValue;
      const accountStatus = user?.fields?.status?.stringValue;

      if (role !== "user" || accountStatus !== "active") {
        return Response.json(
          { error: "Patient account is not authorized." },
          { status: 403 }
        );
      }

      participantName =
        user?.fields?.fullName?.stringValue ??
        user?.fields?.name?.stringValue ??
        "Patient";
    } else {
      if (!doctorId) {
        return Response.json(
          { error: "Assigned doctor is unavailable." },
          { status: 403 }
        );
      }

      const doctor = await getFirestoreDocument(
        `doctors/${doctorId}`,
        firebaseToken
      );

      const doctorFields = doctor?.fields ?? {};

      if (
        doctorFields.userId?.stringValue !== uid ||
        doctorFields.active?.booleanValue !== true ||
        doctorFields.supportsOnline?.booleanValue !== true
      ) {
        return Response.json(
          { error: "You are not authorized to join this consultation." },
          { status: 403 }
        );
      }

      const user = await getFirestoreDocument(
        `users/${uid}`,
        firebaseToken
      );

      if (
        user?.fields?.role?.stringValue !== "doctor" ||
        user?.fields?.status?.stringValue !== "active"
      ) {
        return Response.json(
          { error: "Doctor account is not active." },
          { status: 403 }
        );
      }

      participantName =
        user.fields.fullName?.stringValue ??
        user.fields.name?.stringValue ??
        "Doctor";
    }

	const roomName = `${APPOINTMENT_PREFIX}${appointmentId}`;
	const durableObjectId = env.ROOM_STATE.idFromName(appointmentId);
	const roomState = env.ROOM_STATE.get(durableObjectId);
	const roomStatusResponse = await roomState.fetch(
		"https://room-state.internal/status",
		{
			method: "GET",
		}
	);

	if (!roomStatusResponse.ok) {
		throw new Error("Unable to check consultation room status.");
	}
    // Generate the room name on the server.
    const roomStatus = await roomStatusResponse.json() as {
		roomClosed: boolean;
	};

	if (roomStatus.roomClosed) {
		return Response.json(
			{ error: "This consultation room has been closed." },
			{ status: 403 }
		);
	}
	
	const roomSetupResponse = await roomState.fetch(
		"https://room-state.internal/ensure-room",
		{
			method: "POST",
			headers: {
				"Content-Type": "application/json",
			},
			body: JSON.stringify({
				roomName,
			}),
		}
	);

	if (!roomSetupResponse.ok) {
		const errorData = await roomSetupResponse.json() as { error?: string };
		return Response.json(
			{ error: errorData.error ?? "Unable to prepare the consultation room." },
			{ status: roomSetupResponse.status }
		);
	}

    // Generate a short-lived token for this participant.
    const accessToken = new AccessToken(
      env.LIVEKIT_API_KEY,
      env.LIVEKIT_API_SECRET,
      {
        identity: uid,
        name: participantName,
        ttl: "1h",
      }
    );

    accessToken.addGrant({
      roomJoin: true,
      room: roomName,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
    });

    const token = await accessToken.toJwt();

    return Response.json({
      serverUrl: env.LIVEKIT_URL,
      roomName,
      token,
    });
  } catch (error) {
    console.error("Consultation token error:", error);

    return Response.json(
      { error: "Unable to prepare the consultation room." },
      { status: 500 }
    );
  }
}
async function handleConsultationEnd(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    // 1. Verify Firebase authentication.
    const authorization = request.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    const firebaseToken = authorization.substring(7);

    const { payload } = await jwtVerify(
      firebaseToken,
      FIREBASE_JWKS,
      {
        issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
        audience: FIREBASE_PROJECT_ID,
        algorithms: ["RS256"],
      }
    );

    const uid = payload.sub;

    if (!uid) {
      return Response.json(
        { error: "Invalid user identity." },
        { status: 401 }
      );
    }

    // 2. Validate the appointment ID.
    const body = await request.json() as {
      appointmentId?: string;
    };

    const appointmentId = body.appointmentId;

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "Invalid appointment ID." },
        { status: 400 }
      );
    }

    // 3. Retrieve the appointment using the caller's Firebase token.
    const appointment = await getFirestoreDocument(
      `appointments/${appointmentId}`,
      firebaseToken
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const fields = appointment.fields ?? {};

    const doctorId = fields.doctorId?.stringValue;
    const status = fields.status?.stringValue;
    const mode = fields.mode?.stringValue;
    const isDemo = fields.isDemo?.booleanValue ?? false;

    if (
      status !== "approved" ||
      mode !== "online" ||
      isDemo
    ) {
      return Response.json(
        { error: "This appointment is not eligible for consultation closure." },
        { status: 403 }
      );
    }

    if (!doctorId) {
      return Response.json(
        { error: "Assigned doctor is unavailable." },
        { status: 403 }
      );
    }

    // 4. Verify that the caller is the assigned doctor.
    const doctor = await getFirestoreDocument(
      `doctors/${doctorId}`,
      firebaseToken
    );

    const doctorFields = doctor?.fields ?? {};

    if (
      doctorFields.userId?.stringValue !== uid ||
      doctorFields.active?.booleanValue !== true ||
      doctorFields.supportsOnline?.booleanValue !== true
    ) {
      return Response.json(
        { error: "Only the assigned doctor can end this consultation." },
        { status: 403 }
      );
    }

    // 5. Verify that the doctor's user account is active.
    const user = await getFirestoreDocument(
      `users/${uid}`,
      firebaseToken
    );

    if (
      user?.fields?.role?.stringValue !== "doctor" ||
      user?.fields?.status?.stringValue !== "active"
    ) {
      return Response.json(
        { error: "Doctor account is not authorized." },
        { status: 403 }
      );
    }

    // 6. Close the appointment's LiveKit room.
    const roomName = `${APPOINTMENT_PREFIX}${appointmentId}`;

    const durableObjectId = env.ROOM_STATE.idFromName(appointmentId);
    const roomState = env.ROOM_STATE.get(durableObjectId);

    const endResponse = await roomState.fetch(
      "https://room-state.internal/end-room",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ roomName }),
      }
    );

    const endResult = await endResponse.json() as {
      error?: string;
      success?: boolean;
      alreadyClosed?: boolean;
    };

    if (!endResponse.ok) {
      return Response.json(
        { error: endResult.error ?? "Unable to end the consultation." },
        { status: endResponse.status }
      );
    }

    return Response.json({
      success: true,
      message: "Consultation ended successfully.",
      alreadyClosed: endResult.alreadyClosed ?? false,
    });

  } catch (error) {
    console.error("Consultation end error:", error);

    return Response.json(
      { error: "Unable to end the consultation." },
      { status: 500 }
    );
  }
}

async function getFirestoreDocument(
  documentPath: string,
  firebaseToken: string
): Promise<any | null> {
  const encodedPath = documentPath
    .split("/")
    .map(encodeURIComponent)
    .join("/");

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${encodedPath}`,
    {
      headers: {
        Authorization: `Bearer ${firebaseToken}`,
      },
    }
  );

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    throw new Error(
      `Firestore request failed: ${response.status}`
    );
  }

  return await response.json();
}

async function handleLiveKitWebhook(
  request: Request,
  env: Env
): Promise<Response> {
  const body = await request.text();
  const authorization = request.headers.get("Authorization");

  if (!authorization) {
    return Response.json(
      { error: "Missing webhook authorization." },
      { status: 401 }
    );
  }

  // Verify that this webhook genuinely came from LiveKit.
  const webhookReceiver = new WebhookReceiver(
    env.LIVEKIT_API_KEY,
    env.LIVEKIT_API_SECRET
  );

  let event;

  try {
    event = await webhookReceiver.receive(
      body,
      authorization
    );
  } catch (error) {
    console.error("Invalid LiveKit webhook:", error);

    return Response.json(
      { error: "Invalid webhook signature." },
      { status: 401 }
    );
  }

  // Only participant join and leave events affect the countdown.
  if (
    event.event !== "participant_joined" &&
    event.event !== "participant_left"
  ) {
    return Response.json({
      success: true,
      ignored: true,
    });
  }

  const roomName = event.room?.name;

  if (
    !roomName ||
    !roomName.startsWith(APPOINTMENT_PREFIX)
  ) {
    return Response.json(
      { error: "Invalid consultation room." },
      { status: 400 }
    );
  }

  const appointmentId = roomName.substring(
    APPOINTMENT_PREFIX.length
  );

  if (!/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)) {
    return Response.json(
      { error: "Invalid appointment ID." },
      { status: 400 }
    );
  }

  try {
    // Each appointment has its own Durable Object.
    const durableObjectId =
      env.ROOM_STATE.idFromName(appointmentId);

    const roomState =
      env.ROOM_STATE.get(durableObjectId);

    // The Durable Object checks LiveKit's actual participant list.
    const stateResponse = await roomState.fetch(
      "https://room-state.internal/update",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          roomName,
          eventId: event.id,
        }),
      }
    );

    if (!stateResponse.ok) {
      console.error(
        "Room state update failed:",
        stateResponse.status,
        await stateResponse.text()
      );

      return Response.json(
        { error: "Unable to update consultation room state." },
        { status: 500 }
      );
    }

    return Response.json({
      success: true,
      event: event.event,
      appointmentId,
    });
  } catch (error) {
    console.error("LiveKit room state error:", error);

    return Response.json(
      { error: "Unable to process room event." },
      { status: 500 }
    );
  }
}