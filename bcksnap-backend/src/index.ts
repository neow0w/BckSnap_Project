import { createRemoteJWKSet, jwtVerify, SignJWT, importPKCS8 } from "jose";
import { AccessToken, WebhookReceiver } from "livekit-server-sdk";

export { RoomState } from "./room-state";
export { ProfileSessions } from "./profile-sessions";

interface Env {
  ROOM_STATE: DurableObjectNamespace;
  PROFILE_SESSIONS: DurableObjectNamespace;
  LIVEKIT_URL: string;
  LIVEKIT_API_KEY: string;
  LIVEKIT_API_SECRET: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
  PROFILE_SESSION_SECRET: string;
}

const FIREBASE_PROJECT_ID = "bcksnap-3f858";

function getProfileSessionStorage(
  env: Env,
  clinicAccountUid: string
): DurableObjectStub {
  const id = env.PROFILE_SESSIONS.idFromName(
    clinicAccountUid
  );

  return env.PROFILE_SESSIONS.get(id);
}

interface FirebaseServiceAccount {
  client_email: string;
  private_key: string;
  token_uri: string;
}

interface GoogleOAuthToken {
  access_token: string;
  expires_in: number;
  token_type: string;
}

async function createProfileSessionToken(
  env: Env,
  data: {
    clinicAccountUid: string;
    profileId: string;
    clinicId: string;
    role: string;
    sessionId: string;
  }
): Promise<string> {
  const secretBytes = new TextEncoder().encode(
    env.PROFILE_SESSION_SECRET
  );

  if (secretBytes.length < 32) {
    throw new Error("Profile session secret is too short.");
  }

  return await new SignJWT({
    clinicAccountUid: data.clinicAccountUid,
    profileId: data.profileId,
    clinicId: data.clinicId,
    role: data.role,
    sessionId: data.sessionId,
  })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("8h")
    .setIssuer("bcksnap-backend")
    .setAudience("bcksnap-staff")
    .sign(secretBytes);
}

async function getGoogleAccessToken(
  env: Env
): Promise<string> {
  const serviceAccount = JSON.parse(
    env.FIREBASE_SERVICE_ACCOUNT_JSON
  ) as FirebaseServiceAccount;

  if (
    !serviceAccount.client_email ||
    !serviceAccount.private_key ||
    !serviceAccount.token_uri
  ) {
    throw new Error("Invalid Firebase service account configuration.");
  }

  const privateKey = await importPKCS8(
    serviceAccount.private_key,
    "RS256"
  );

  const now = Math.floor(Date.now() / 1000);

  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/datastore",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(serviceAccount.client_email)
    .setSubject(serviceAccount.client_email)
    .setAudience(serviceAccount.token_uri)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(privateKey);

  const response = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  if (!response.ok) {
    throw new Error(
      `Google OAuth failed with status ${response.status}.`
    );
  }

  const token = await response.json() as GoogleOAuthToken;

  if (!token.access_token) {
    throw new Error("Google OAuth did not return an access token.");
  }

  return token.access_token;
}

function encodeBase64Url(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

async function hashProfilePassword(

  salt: string,
  password: string
): Promise<string> {
  const encoder = new TextEncoder();

  let bytes = encoder.encode(`${salt}:${password}`);

  for (let i = 0; i < 10000; i++) {
    const digest = await crypto.subtle.digest("SHA-256", bytes);
    bytes = new Uint8Array(digest);
  }

  return encodeBase64Url(bytes);
}

async function verifyProfilePassword(
  salt: string,
  password: string,
  expectedHash: string
): Promise<boolean> {
  const actualHash = await hashProfilePassword(salt, password);

  if (actualHash.length !== expectedHash.length) {
    return false;
  }

  let difference = 0;

  for (let i = 0; i < actualHash.length; i++) {
    difference |= actualHash.charCodeAt(i) ^
      expectedHash.charCodeAt(i);
  }

  return difference === 0;
}


async function getFirestoreDocumentAsAdmin(
  documentPath: string,
  env: Env
): Promise<any | null> {
  const accessToken = await getGoogleAccessToken(env);

  const encodedPath = documentPath
    .split("/")
    .map(encodeURIComponent)
    .join("/");

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${encodedPath}`,
    {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
      },
    }
  );

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    throw new Error(
      `Firestore admin read failed with status ${response.status}.`
    );
  }

  return await response.json();
}


async function updateFirestoreDocumentAsAdmin(
  documentPath: string,
  fields: Record<string, unknown>,
  env: Env,
  expectedUpdateTime?: string
): Promise<void> {
  const accessToken = await getGoogleAccessToken(env);

  const encodedPath = documentPath
    .split("/")
    .map(encodeURIComponent)
    .join("/");

  const params = new URLSearchParams();

  for (const field of Object.keys(fields)) {
    params.append("updateMask.fieldPaths", field);
  }

  if (expectedUpdateTime) {
    params.set("currentDocument.updateTime", expectedUpdateTime);
  }

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${encodedPath}?${params.toString()}`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields }),
    }
  );

  if (!response.ok) {
    throw new Error(
      `Firestore admin update failed with status ${response.status}.`
    );
  }
}

const FIREBASE_JWKS = createRemoteJWKSet(
  new URL(
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com"
  )
);

const APPOINTMENT_PREFIX = "bcksnap_appointment_";
const JOIN_WINDOW_MINUTES = 15;

function getCorsHeaders(origin: string | null) {
  const allowedOrigin =
    origin && /^https?:\/\/(localhost|127\.0\.0\.1):\d+$/.test(origin)
      ? origin
      : "";

  return {
    ...(allowedOrigin
      ? { "Access-Control-Allow-Origin": allowedOrigin }
      : {}),
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Authorization, Content-Type",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}


async function createFirestoreDocumentAsAdmin(
  parentPath: string,
  collectionId: string,
  fields: Record<string, unknown>,
  env: Env
): Promise<any> {
  const accessToken = await getGoogleAccessToken(env);

  const encodedParentPath = parentPath
    .split("/")
    .map(encodeURIComponent)
    .join("/");

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${encodedParentPath}/${encodeURIComponent(collectionId)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields }),
    }
  );

  if (!response.ok) {
    throw new Error(
      `Firestore admin create failed with status ${response.status}.`
    );
  }

  return await response.json();
}

async function queryFirestoreAsAdmin(
  structuredQuery: Record<string, unknown>,
  env: Env
): Promise<any[]> {
  const accessToken = await getGoogleAccessToken(env);

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents:runQuery`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        structuredQuery,
      }),
    }
  );

  if (!response.ok) {
    throw new Error(
      `Firestore query failed with status ${response.status}.`
    );
  }

  const results = await response.json() as Array<{
    document?: any;
  }>;

  return results
    .filter((result) => result.document)
    .map((result) => result.document);
}


async function createTopLevelFirestoreDocumentAsAdmin(
  collectionId: string,
  documentId: string,
  fields: Record<string, unknown>,
  env: Env
): Promise<void> {
  const accessToken = await getGoogleAccessToken(env);

  const response = await fetch(
    `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${encodeURIComponent(collectionId)}?documentId=${encodeURIComponent(documentId)}`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ fields }),
    }
  );

  if (!response.ok) {
    throw new Error(
      `Firestore notification creation failed with status ${response.status}.`
    );
  }
}


async function handleNotifyAppointmentBooking(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    // 1. Authenticate the patient using their Firebase ID token.
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    let patientUid: string;

    try {
      const { payload } = await jwtVerify(
        token,
        FIREBASE_JWKS,
        {
          issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
          audience: FIREBASE_PROJECT_ID,
          algorithms: ["RS256"],
        }
      );

      if (typeof payload.sub !== "string") {
        throw new Error("Invalid patient identity.");
      }

      patientUid = payload.sub;
    } catch {
      return Response.json(
        { error: "Invalid patient authentication token." },
        { status: 401 }
      );
    }

    // 2. Validate the appointment ID.
    const body = await request.json() as {
      appointmentId?: unknown;
    };

    const appointmentId = body.appointmentId;

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "A valid appointment ID is required." },
        { status: 400 }
      );
    }

    // 3. Retrieve the appointment using privileged Firestore access.
    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const appointmentFields = appointment.fields ?? {};

    // The caller must own this appointment.
    if (appointmentFields.userId?.stringValue !== patientUid) {
      return Response.json(
        { error: "You are not authorized to notify staff about this appointment." },
        { status: 403 }
      );
    }

    if (appointmentFields.status?.stringValue !== "pending") {
      return Response.json(
        { error: "Only pending appointments can trigger booking notifications." },
        { status: 409 }
      );
    }

    // Demo appointments should not generate real staff notifications.
    if (appointmentFields.isDemo?.booleanValue === true) {
      return Response.json({
        success: true,
        message: "Demo appointment skipped.",
        notificationsCreated: 0,
      });
    }

    const clinicId = appointmentFields.clinicId?.stringValue;
    const doctorId = appointmentFields.doctorId?.stringValue;
    const patientName =
      appointmentFields.patientName?.stringValue ?? "A patient";
    const reference =
      appointmentFields.reference?.stringValue ?? appointmentId;

    if (!clinicId || !doctorId) {
      return Response.json(
        { error: "Appointment is missing clinic or doctor information." },
        { status: 400 }
      );
    }


    // 4. Retrieve the assigned provider and verify their active profile.
    const providerProfile = await getFirestoreDocumentAsAdmin(
      `staffProfiles/${doctorId}`,
      env
    );

    const providerFields = providerProfile?.fields ?? {};

    const recipients = new Map<string, string>();

    const providerRole = providerFields.role?.stringValue;

    if (
      providerFields.clinicId?.stringValue === clinicId &&
      (providerRole === "doctor" || providerRole === "pt") &&
      providerFields.status?.stringValue === "active"
    ) {
      recipients.set(doctorId, providerRole);
    }

    // 5. Retrieve all active receptionists assigned to this clinic.
    const receptionists = await queryFirestoreAsAdmin(
      {
        from: [{ collectionId: "staffProfiles" }],
        where: {
          fieldFilter: {
            field: { fieldPath: "clinicId" },
            op: "EQUAL",
            value: { stringValue: clinicId },
          },
        },
      },
      env
    );

    for (const profile of receptionists) {
      const fields = profile.fields ?? {};
      const nameParts = String(profile.name ?? "").split("/");
      const profileId = nameParts[nameParts.length - 1];

      if (
        profileId &&
        fields.clinicId?.stringValue === clinicId &&
        fields.role?.stringValue === "receptionist" &&
        fields.status?.stringValue === "active"
      ) {
        recipients.set(profileId, "receptionist");
      }
    }

    // 6. Create one notification for each eligible staff profile.
    let notificationsCreated = 0;

    for (const profileId of recipients.keys()) {
      // Check existing notification first to prevent duplicates.
      const notificationId = `booking_${appointmentId}_${profileId}`;

      const existing = await getFirestoreDocumentAsAdmin(
        `notifications/${notificationId}`,
        env
      );

      if (existing) {
        continue;
      }

      // Missing preferences default to enabled.
      // Preference-read failures also default to unread notifications.
      let shouldBeUnread = true;

      try {
        const preferences = await getFirestoreDocumentAsAdmin(
          `staffNotificationPreferences/${profileId}`,
          env
        );

        const preferenceFields = preferences?.fields ?? {};
        const categories =
          preferenceFields.categories?.mapValue?.fields ?? {};

        const enabled =
          preferenceFields.enabled?.booleanValue ?? true;

        const appointmentsEnabled =
          categories.appointments?.booleanValue ?? true;

        shouldBeUnread = enabled && appointmentsEnabled;
      } catch (error) {
        console.error(
          `Unable to read notification preferences for ${profileId}:`,
          error
        );
        // If preferences cannot be read, create the notification as unread.
        shouldBeUnread = true;
      }

      const fields = {
        recipientType: { stringValue: "staff" },
        recipientId: { stringValue: profileId },
        clinicId: { stringValue: clinicId },
        appointmentId: { stringValue: appointmentId },
        eventType: { stringValue: "new_booking" },
        title: { stringValue: "New appointment booking" },
        message: {
          stringValue: `${patientName} booked an appointment with the clinic. Reference: ${reference}.`,
        },
        read: { booleanValue: !shouldBeUnread },
        createdAt: { timestampValue: new Date().toISOString() },
      };

      try {
        await createTopLevelFirestoreDocumentAsAdmin(
          "notifications",
          notificationId,
          fields,
          env
        );

        notificationsCreated++;
      } catch (error) {
        // A concurrent retry may have created the same notification.
        const createdByAnotherRequest =
          await getFirestoreDocumentAsAdmin(
            `notifications/${notificationId}`,
            env
          );

        if (!createdByAnotherRequest) {
          throw error;
        }
      }
    }

    return Response.json({
      success: true,
      message: "Appointment booking notifications processed.",
      notificationsCreated,
    });
  } catch (error) {
    console.error("Appointment booking notification error:", error);

    return Response.json(
      { error: "Unable to process appointment booking notifications." },
      { status: 500 }
    );
  }
}


async function handleGetStaffNotifications(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    let staff: AuthenticatedStaffProfile;

    try {
      staff = await authenticateStaffProfile(request, env);
    } catch {
      return Response.json(
        { error: "Invalid or expired staff profile session." },
        { status: 401 }
      );
    }

    const documents = await queryFirestoreAsAdmin(
      {
        from: [
          {
            collectionId: "notifications",
          },
        ],
        where: {
          compositeFilter: {
            op: "AND",
            filters: [
              {
                fieldFilter: {
                  field: { fieldPath: "recipientType" },
                  op: "EQUAL",
                  value: { stringValue: "staff" },
                },
              },
              {
                fieldFilter: {
                  field: { fieldPath: "recipientId" },
                  op: "EQUAL",
                  value: { stringValue: staff.profileId },
                },
              },
              {
                fieldFilter: {
                  field: { fieldPath: "clinicId" },
                  op: "EQUAL",
                  value: { stringValue: staff.clinicId },
                },
              },
            ],
          },
        },
        orderBy: [
          {
            field: { fieldPath: "createdAt" },
            direction: "DESCENDING",
          },
        ],
        limit: 50,
      },
      env
    );

    const notifications = documents.map((document) => {
      const fields = document.fields ?? {};
      const nameParts = String(document.name ?? "").split("/");

      return {
        id: nameParts[nameParts.length - 1],
        appointmentId: fields.appointmentId?.stringValue ?? "",
        eventType: fields.eventType?.stringValue ?? "",
        title: fields.title?.stringValue ?? "",
        message: fields.message?.stringValue ?? "",
        createdAt: fields.createdAt?.timestampValue ?? null,
        read: fields.read?.booleanValue ?? false,
      };
    });

    return Response.json({
      success: true,
      notifications,
    });
  } catch (error) {
    console.error("Get staff notifications error:", error);

    return Response.json(
      { error: "Unable to load staff notifications." },
      { status: 500 }
    );
  }
}

async function handleMarkStaffNotificationRead(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    let staff: AuthenticatedStaffProfile;

    try {
      staff = await authenticateStaffProfile(request, env);
    } catch {
      return Response.json(
        { error: "Invalid or expired staff profile session." },
        { status: 401 }
      );
    }

    const body = await request.json() as {
      notificationId?: unknown;
    };

    const notificationId = body.notificationId;

    if (
      typeof notificationId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(notificationId)
    ) {
      return Response.json(
        { error: "A valid notification ID is required." },
        { status: 400 }
      );
    }

    const notification = await getFirestoreDocumentAsAdmin(
      `notifications/${notificationId}`,
      env
    );

    if (!notification) {
      return Response.json(
        { error: "Notification not found." },
        { status: 404 }
      );
    }

    const fields = notification.fields ?? {};

    if (
      fields.recipientType?.stringValue !== "staff" ||
      fields.recipientId?.stringValue !== staff.profileId ||
      fields.clinicId?.stringValue !== staff.clinicId
    ) {
      return Response.json(
        { error: "You are not authorized to update this notification." },
        { status: 403 }
      );
    }

    if (typeof notification.updateTime !== "string") {
      return Response.json(
        { error: "Notification could not be updated. Please try again." },
        { status: 409 }
      );
    }

    await updateFirestoreDocumentAsAdmin(
      `notifications/${notificationId}`,
      {
        read: { booleanValue: true },
      },
      env,
      notification.updateTime
    );

    return Response.json({
      success: true,
      message: "Notification marked as read.",
    });
  } catch (error) {
    console.error("Mark staff notification read error:", error);

    return Response.json(
      { error: "Unable to update staff notification." },
      { status: 500 }
    );
  }
}

async function handleGetStaffNotificationPreferences(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    let staff: AuthenticatedStaffProfile;

    try {
      staff = await authenticateStaffProfile(request, env);
    } catch {
      return Response.json(
        { error: "Invalid or expired staff profile session." },
        { status: 401 }
      );
    }

    const document = await getFirestoreDocumentAsAdmin(
      `staffNotificationPreferences/${staff.profileId}`,
      env
    );

    const fields = document?.fields ?? {};

    const categories = fields.categories?.mapValue?.fields ?? {};

    return Response.json({
      success: true,
      preferences: {
        enabled: fields.enabled?.booleanValue ?? true,
        categories: {
          appointments: categories.appointments?.booleanValue ?? true,
          consultations: categories.consultations?.booleanValue ?? true,
          messages: categories.messages?.booleanValue ?? true,
          system: categories.system?.booleanValue ?? true,
        },
      },
    });
  } catch (error) {
    console.error("Get staff notification preferences error:", error);

    return Response.json(
      { error: "Unable to load notification preferences." },
      { status: 500 }
    );
  }
}

async function handleUpdateStaffNotificationPreferences(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    let staff: AuthenticatedStaffProfile;

    try {
      staff = await authenticateStaffProfile(request, env);
    } catch {
      return Response.json(
        { error: "Invalid or expired staff profile session." },
        { status: 401 }
      );
    }

    const body = await request.json() as {
      enabled?: unknown;
      categories?: {
        appointments?: unknown;
        consultations?: unknown;
        messages?: unknown;
        system?: unknown;
      };
    };

    if (
      typeof body.enabled !== "boolean" ||
      !body.categories ||
      typeof body.categories !== "object" ||
      typeof body.categories.appointments !== "boolean" ||
      typeof body.categories.consultations !== "boolean" ||
      typeof body.categories.messages !== "boolean" ||
      typeof body.categories.system !== "boolean"
    ) {
      return Response.json(
        { error: "Invalid notification preferences." },
        { status: 400 }
      );
    }

    const fields = {
      clinicId: { stringValue: staff.clinicId },
      recipientId: { stringValue: staff.profileId },
      enabled: { booleanValue: body.enabled },
      categories: {
        mapValue: {
          fields: {
            appointments: {
              booleanValue: body.categories.appointments,
            },
            consultations: {
              booleanValue: body.categories.consultations,
            },
            messages: {
              booleanValue: body.categories.messages,
            },
            system: {
              booleanValue: body.categories.system,
            },
          },
        },
      },
      updatedAt: {
        timestampValue: new Date().toISOString(),
      },
    };

    const existingDocument = await getFirestoreDocumentAsAdmin(
      `staffNotificationPreferences/${staff.profileId}`,
      env
    );

    const accessToken = await getGoogleAccessToken(env);

    let response: Response;

    if (existingDocument) {
      if (typeof existingDocument.updateTime !== "string") {
        return Response.json(
          { error: "Preferences could not be updated. Please try again." },
          { status: 409 }
        );
      }

      const params = new URLSearchParams();

      params.append("updateMask.fieldPaths", "clinicId");
      params.append("updateMask.fieldPaths", "recipientId");
      params.append("updateMask.fieldPaths", "enabled");
      params.append("updateMask.fieldPaths", "categories");
      params.append("updateMask.fieldPaths", "updatedAt");

      params.set(
        "currentDocument.updateTime",
        existingDocument.updateTime
      );

      response = await fetch(
        `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/staffNotificationPreferences/${encodeURIComponent(staff.profileId)}?${params.toString()}`,
        {
          method: "PATCH",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ fields }),
        }
      );
    } else {
      response = await fetch(
        `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/staffNotificationPreferences?documentId=${encodeURIComponent(staff.profileId)}`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ fields }),
        }
      );
    }

    if (!response.ok) {
      console.error(
        "Firestore notification preferences write failed:",
        response.status,
        await response.text()
      );

      return Response.json(
        { error: "Unable to save notification preferences." },
        { status: response.status === 409 ? 409 : 500 }
      );
    }

    return Response.json({
      success: true,
      message: "Notification preferences saved.",
    });
  } catch (error) {
    console.error("Update staff notification preferences error:", error);

    return Response.json(
      { error: "Unable to save notification preferences." },
      { status: 500 }
    );
  }
}

async function handleGoogleAuthTest(
  _request: Request,
  env: Env
): Promise<Response> {
  try {
    const accessToken = await getGoogleAccessToken(env);

    const response = await fetch(
      `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      }
    );

    if (!response.ok) {
      console.error(
        "Firestore connection test failed:",
        response.status
      );

      return Response.json(
        {
          success: false,
          message: "Firestore access was denied.",
        },
        { status: 502 }
      );
    }

    return Response.json({
      success: true,
      message: "Google authentication and Firestore access succeeded.",
    });
  } catch (error) {
    console.error("Google authentication test failed:", error);

    return Response.json(
      {
        success: false,
        message: "Google authentication test failed.",
      },
      { status: 500 }
    );
  }
}

async function handleProfileSession(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    const authorization = request.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    const firebaseToken = authorization.substring(7);

    // Verify the shared clinic account's Firebase ID token.
    const { payload } = await jwtVerify(
      firebaseToken,
      FIREBASE_JWKS,
      {
        issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
        audience: FIREBASE_PROJECT_ID,
        algorithms: ["RS256"],
      }
    );

    const clinicAccountUid = payload.sub;

    if (!clinicAccountUid) {
      return Response.json(
        { error: "Invalid user identity." },
        { status: 401 }
      );
    }

    const body = await request.json() as {
      profileId?: string;
      password?: string;
    };

    const { profileId, password } = body;

    if (
      typeof profileId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(profileId) ||
      typeof password !== "string" ||
      password.length === 0 ||
      password.length > 256
    ) {
      return Response.json(
        { error: "Invalid profile login details." },
        { status: 400 }
      );
    }

    // Verify the shared clinic account using privileged Firestore access.
    const clinicAccount = await getFirestoreDocumentAsAdmin(
      `users/${clinicAccountUid}`,
      env
    );

    const accountFields = clinicAccount?.fields ?? {};

    if (
      accountFields.role?.stringValue !== "clinic_staff" ||
      accountFields.status?.stringValue !== "active"
    ) {
      return Response.json(
        { error: "Clinic account is not authorized." },
        { status: 403 }
      );
    }

    const clinicId = accountFields.clinicId?.stringValue;

    if (!clinicId) {
      return Response.json(
        { error: "Clinic account has no assigned clinic." },
        { status: 403 }
      );
    }

    // Retrieve the selected staff profile.
    const profile = await getFirestoreDocumentAsAdmin(
      `staffProfiles/${profileId}`,
      env
    );

    if (!profile) {
      return Response.json(
        { error: "Profile not found." },
        { status: 404 }
      );
    }

    const profileFields = profile.fields ?? {};

    const profileClinicId = profileFields.clinicId?.stringValue;
    const role = profileFields.role?.stringValue;
    const status = profileFields.status?.stringValue;
    const salt = profileFields.passwordSalt?.stringValue;
    const passwordHash = profileFields.passwordHash?.stringValue;

    if (
      profileClinicId !== clinicId ||
      status !== "active" ||
      (role !== "doctor" && role !== "receptionist" && role !== "pt")
    ) {
      return Response.json(
        { error: "This profile is not available." },
        { status: 403 }
      );
    }

    if (!salt || !passwordHash) {
      return Response.json(
        { error: "Profile authentication is not configured." },
        { status: 403 }
      );
    }

    // Verify the profile password on the backend.
    const passwordValid = await verifyProfilePassword(
      salt,
      password,
      passwordHash
    );

    if (!passwordValid) {
      return Response.json(
        { error: "Incorrect profile password." },
        { status: 401 }
      );
    }

    // Activate a new session, replacing the previous profile session.
    const sessionId = crypto.randomUUID();
    const expiresAt = Date.now() + 8 * 60 * 60 * 1000;

    const sessionStorage = getProfileSessionStorage(
      env,
      clinicAccountUid
    );

    const token = await createProfileSessionToken(env, {
      clinicAccountUid,
      profileId,
      clinicId,
      role,
      sessionId,
    });

    const activationResponse = await sessionStorage.fetch(
      "https://profile-session.internal/activate",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          sessionId,
          profileId,
          clinicId,
          role,
          expiresAt,
        }),
      }
    );

    if (!activationResponse.ok) {
      throw new Error("Unable to activate profile session.");
    }

    // Issue the signed profile-session token.


    return Response.json({
      success: true,
      token,
      expiresAt,
      profile: {
        id: profileId,
        name: profileFields.name?.stringValue ?? "",
        role,
        clinicId,
      },
    });
  } catch (error) {
    console.error("Profile session error:", error);

    return Response.json(
      { error: "Unable to start the profile session." },
      { status: 500 }
    );
  }
}

async function handleProfileSessionValidation(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    const authorization = request.headers.get("Authorization");

    if (!authorization?.startsWith("Bearer ")) {
      return Response.json(
        { error: "Profile session required." },
        { status: 401 }
      );
    }

    const token = authorization.substring(7);

    const secretBytes = new TextEncoder().encode(
      env.PROFILE_SESSION_SECRET
    );

    const { payload } = await jwtVerify(
      token,
      secretBytes,
      {
        issuer: "bcksnap-backend",
        audience: "bcksnap-staff",
        algorithms: ["HS256"],
      }
    );

    const clinicAccountUid = payload.clinicAccountUid;
    const profileId = payload.profileId;
    const clinicId = payload.clinicId;
    const role = payload.role;
    const sessionId = payload.sessionId;

    if (
      typeof clinicAccountUid !== "string" ||
      typeof profileId !== "string" ||
      typeof clinicId !== "string" ||
      typeof role !== "string" ||
      typeof sessionId !== "string" ||
      !["doctor", "receptionist", "pt"].includes(role)
    ) {
      return Response.json(
        { error: "Invalid profile session." },
        { status: 401 }
      );
    }

    const sessionStorage = getProfileSessionStorage(
      env,
      clinicAccountUid
    );

    const validationResponse = await sessionStorage.fetch(
      "https://profile-session.internal/validate",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          sessionId,
          profileId,
          clinicId,
          role,
        }),
      }
    );

    if (!validationResponse.ok) {
      return Response.json(
        { error: "Profile session is no longer active." },
        { status: 401 }
      );
    }

    const result = await validationResponse.json() as {
      active?: boolean;
    };

    if (result.active !== true) {
      return Response.json(
        { error: "Profile session is no longer active." },
        { status: 401 }
      );
    }

    // Recheck the clinic account's current status.
    const clinicAccount = await getFirestoreDocumentAsAdmin(
      `users/${clinicAccountUid}`,
      env
    );

    const accountFields = clinicAccount?.fields ?? {};

    if (
      accountFields.role?.stringValue !== "clinic_staff" ||
      accountFields.status?.stringValue !== "active" ||
      accountFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "Clinic account is no longer authorized." },
        { status: 403 }
      );
    }

    // Recheck the selected staff profile's current status.
    const profile = await getFirestoreDocumentAsAdmin(
      `staffProfiles/${profileId}`,
      env
    );

    const profileFields = profile?.fields ?? {};

    if (
      profileFields.clinicId?.stringValue !== clinicId ||
      profileFields.status?.stringValue !== "active" ||
      profileFields.role?.stringValue !== role
    ) {
      return Response.json(
        { error: "Staff profile is no longer authorized." },
        { status: 403 }
      );
    }

    return Response.json({
      valid: true,
      clinicAccountUid,
      sessionId,
      profile: {
        id: profileId,
        clinicId,
        role,
      },
    });
  } catch {
    return Response.json(
      { error: "Invalid or expired profile session." },
      { status: 401 }
    );
  }
}

type AuthenticatedStaffProfile = {
  clinicAccountUid: string;
  profileId: string;
  clinicId: string;
  role: string;
  sessionId: string;
};

async function authenticateStaffProfile(
  request: Request,
  env: Env
): Promise<AuthenticatedStaffProfile> {
  const validationResponse = await handleProfileSessionValidation(
    request,
    env
  );

  if (!validationResponse.ok) {
    throw new Error("Invalid or expired staff profile session.");
  }

  const body = await validationResponse.json() as {
    valid?: boolean;
    clinicAccountUid?: string;
    sessionId?: string;
    profile?: {
      id?: string;
      clinicId?: string;
      role?: string;
    };
  };

  const profile = body.profile;

  if (
    body.valid !== true ||
    !body.clinicAccountUid ||
    !body.sessionId ||
    !profile?.id ||
    !profile.clinicId ||
    !profile.role
  ) {
    throw new Error("Unable to verify staff profile.");
  }

  return {
    clinicAccountUid: body.clinicAccountUid,
    profileId: profile.id,
    clinicId: profile.clinicId,
    role: profile.role,
    sessionId: body.sessionId,
  };
}

async function handleCompleteAppointment(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Profile session required." },
        { status: 401 }
      );
    }

    const secret = env.PROFILE_SESSION_SECRET;
    const { payload } = await jwtVerify(
      token,
      new TextEncoder().encode(secret),
      {
        issuer: "bcksnap-backend",
        audience: "bcksnap-staff",
        algorithms: ["HS256"],
      }
    );

    const clinicAccountUid = payload.clinicAccountUid;
    const profileId = payload.profileId;
    const clinicId = payload.clinicId;
    const role = payload.role;
    const sessionId = payload.sessionId;

    if (
      typeof clinicAccountUid !== "string" ||
      typeof profileId !== "string" ||
      typeof clinicId !== "string" ||
      typeof sessionId !== "string" ||
      role !== "doctor"
    ) {
      return Response.json(
        { error: "Only an active doctor profile can complete appointments." },
        { status: 403 }
      );
    }

    const sessionStub = env.PROFILE_SESSIONS.get(
      env.PROFILE_SESSIONS.idFromName(clinicAccountUid)
    );

    const sessionResponse = await sessionStub.fetch(
      "https://profile-session/validate",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sessionId,
          profileId,
          clinicId,
          role,
        }),
      }
    );

    if (!sessionResponse.ok) {
      return Response.json(
        { error: "Profile session is no longer active." },
        { status: 401 }
      );
    }

    const clinicAccount = await getFirestoreDocumentAsAdmin(
      `users/${clinicAccountUid}`,
      env
    );

    const accountFields = clinicAccount?.fields ?? {};

    if (
      accountFields.role?.stringValue !== "clinic_staff" ||
      accountFields.status?.stringValue !== "active" ||
      accountFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "Clinic staff account is not authorized." },
        { status: 403 }
      );
    }

    const staffProfile = await getFirestoreDocumentAsAdmin(
      `staffProfiles/${profileId}`,
      env
    );

    const profileFields = staffProfile?.fields ?? {};

    if (
      profileFields.clinicId?.stringValue !== clinicId ||
      profileFields.status?.stringValue !== "active" ||
      profileFields.role?.stringValue !== "doctor"
    ) {
      return Response.json(
        { error: "Doctor profile is not authorized." },
        { status: 403 }
      );
    }

    const body = await request.json() as {
      appointmentId?: unknown;
    };

    const appointmentId = body.appointmentId;

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "A valid appointment ID is required." },
        { status: 400 }
      );
    }

    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const appointmentFields = appointment.fields ?? {};

    if (
      appointmentFields.doctorId?.stringValue !== profileId ||
      appointmentFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "You are not authorized to complete this appointment." },
        { status: 403 }
      );
    }

    if (appointmentFields.status?.stringValue !== "approved") {
      return Response.json(
        { error: "Only approved appointments can be completed." },
        { status: 409 }
      );
    }

    if (typeof appointment.updateTime !== "string") {
      return Response.json(
        { error: "Appointment could not be safely updated. Refresh and try again." },
        { status: 409 }
      );
    }

    const now = new Date().toISOString();

    await updateFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      {
        status: { stringValue: "completed" },
        completedAt: { timestampValue: now },
        updatedAt: { timestampValue: now },
      },
      env,
      appointment.updateTime
    );

    return Response.json({
      success: true,
      message: "Appointment marked as completed.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "";

    if (message.includes("status 409")) {
      return Response.json(
        { error: "Appointment changed. Refresh and try again." },
        { status: 409 }
      );
    }

    console.error("Complete appointment error:", error);

    return Response.json(
      { error: "Unable to complete appointment." },
      { status: 500 }
    );
  }
}

async function handleProfileSessionRevoke(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    const authHeader = request.headers.get("Authorization");
    const token = authHeader?.startsWith("Bearer ")
      ? authHeader.substring(7)
      : null;

    if (!token) {
      return Response.json(
        { error: "Missing session token." },
        { status: 401 }
      );
    }

    const secretBytes = new TextEncoder().encode(
      env.PROFILE_SESSION_SECRET
    );

    const { payload } = await jwtVerify(token, secretBytes, {
      algorithms: ["HS256"],
      issuer: "bcksnap-backend",
      audience: "bcksnap-staff",
    });

    const clinicAccountUid = payload.clinicAccountUid;
    const sessionId = payload.sessionId;

    if (
      typeof clinicAccountUid !== "string" ||
      typeof sessionId !== "string"
    ) {
      return Response.json(
        { error: "Invalid session." },
        { status: 401 }
      );
    }

    const storage = getProfileSessionStorage(
      env,
      clinicAccountUid
    );

    const response = await storage.fetch(
      "https://profile-session/revoke",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ sessionId }),
      }
    );

    if (!response.ok) {
      return Response.json(
        { error: "Unable to revoke session." },
        { status: 500 }
      );
    }

    return Response.json({ success: true });
  } catch {
    return Response.json(
      { error: "Invalid or expired session." },
      { status: 401 }
    );
  }
}

export default {
  async fetch(
    request: Request,
    env: Env
  ): Promise<Response> {
    const url = new URL(request.url);
    const corsHeaders = getCorsHeaders(request.headers.get("Origin"));

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,
        headers: corsHeaders,
      });
    }


    let response: Response;

    if (
      request.method === "POST" &&
      url.pathname === "/api/profile/session"
    ) {
      response = await handleProfileSession(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/profile/session/validate"
    ) {
      response = await handleProfileSessionValidation(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/profile/session/revoke"
    ) {
      response = await handleProfileSessionRevoke(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/appointments/notify-booking"
    ) {
      response = await handleNotifyAppointmentBooking(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/staff/notifications"
    ) {
      response = await handleGetStaffNotifications(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/staff/notifications/read"
    ) {
      response = await handleMarkStaffNotificationRead(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/staff/notifications/preferences"
    ) {
      response = await handleGetStaffNotificationPreferences(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/staff/notifications/preferences/update"
    ) {
      response = await handleUpdateStaffNotificationPreferences(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/appointments/complete"
    ) {
      response = await handleCompleteAppointment(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/consultation/token"
    ) {
      response = await handleConsultationToken(request, env);

    } else if (
      request.method === "GET" &&
      url.pathname === "/api/consultation/messages"
    ) {
      response = await handleGetConsultationMessages(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/consultation/messages"
    ) {
      response = await handleSendConsultationMessage(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/consultation/end"
    ) {
      response = await handleConsultationEnd(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/consultation/start-instant"
    ) {
      response = await handleInstantMeetingStart(request, env);
    } else if (
      request.method === "POST" &&
      url.pathname === "/api/livekit/webhook"
    ) {
      response = await handleLiveKitWebhook(request, env);
    } else {
      response = Response.json(
        { error: "Not found" },
        { status: 404 }
      );
    }

    const headers = new Headers(response.headers);

    for (const [key, value] of Object.entries(corsHeaders)) {
      headers.set(key, value);
    }

    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers,
    });
  },
} satisfies ExportedHandler<Env>;



async function handleConsultationToken(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    // 1. Read the authorization token.
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    // 2. Identify the authentication type.
    let patientUid: string | null = null;
    let clinicAccountUid: string | null = null;
    let profileId: string | null = null;
    let clinicId: string | null = null;
    let sessionId: string | null = null;
    let participantIdentity = "";
    let participantName = "";

    // First, try doctor profile-session authentication.
    try {
      const { payload } = await jwtVerify(
        token,
        new TextEncoder().encode(env.PROFILE_SESSION_SECRET),
        {
          issuer: "bcksnap-backend",
          audience: "bcksnap-staff",
          algorithms: ["HS256"],
        }
      );

      if (
        typeof payload.clinicAccountUid === "string" &&
        typeof payload.profileId === "string" &&
        typeof payload.clinicId === "string" &&
        typeof payload.sessionId === "string" &&
        payload.role === "doctor"
      ) {
        clinicAccountUid = payload.clinicAccountUid;
        profileId = payload.profileId;
        clinicId = payload.clinicId;
        sessionId = payload.sessionId;
      }
    } catch (_) {
      // Not a valid doctor profile-session token.
    }

    // If no valid doctor profile was identified, try patient Firebase authentication.
    if (!profileId) {
      try {
        const { payload } = await jwtVerify(
          token,
          FIREBASE_JWKS,
          {
            issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
            audience: FIREBASE_PROJECT_ID,
            algorithms: ["RS256"],
          }
        );

        if (typeof payload.sub !== "string") {
          return Response.json(
            { error: "Invalid user identity." },
            { status: 401 }
          );
        }

        patientUid = payload.sub;
      } catch (_) {
        return Response.json(
          { error: "Invalid authentication token." },
          { status: 401 }
        );
      }
    }

    // 3. Validate the appointment ID.
    const body = await request.json() as {
      appointmentId?: unknown;
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

    // 4. Retrieve the appointment using server-side credentials.
    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
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
    const appointmentClinicId = fields.clinicId?.stringValue;
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
        {
          error: "This appointment is not eligible for an online consultation.",
        },
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

    if (!Number.isFinite(scheduledTime)) {
      return Response.json(
        { error: "Invalid appointment schedule." },
        { status: 400 }
      );
    }

    // 5. Authorize the patient or assigned doctor.
    if (patientUid !== null) {
      // Patient authentication.
      if (patientUid !== patientId) {
        return Response.json(
          { error: "You are not authorized to join this consultation." },
          { status: 403 }
        );
      }

      const user = await getFirestoreDocumentAsAdmin(
        `users/${patientUid}`,
        env
      );

      const userFields = user?.fields ?? {};

      if (
        userFields.role?.stringValue !== "user" ||
        userFields.status?.stringValue !== "active"
      ) {
        return Response.json(
          { error: "Patient account is not authorized." },
          { status: 403 }
        );
      }

      participantIdentity = patientUid;
      participantName =
        userFields.fullName?.stringValue ??
        userFields.name?.stringValue ??
        "Patient";
    } else {
      // Doctor profile-session authentication.
      if (
        !clinicAccountUid ||
        !profileId ||
        !clinicId ||
        !sessionId
      ) {
        return Response.json(
          { error: "Invalid doctor profile session." },
          { status: 401 }
        );
      }

      // Confirm that the selected profile is still the assigned doctor.
      if (
        doctorId !== profileId ||
        !appointmentClinicId ||
        appointmentClinicId !== clinicId
      ) {
        return Response.json(
          { error: "You are not authorized to join this consultation." },
          { status: 403 }
        );
      }

      // Validate the active profile session.
      const sessionStub = env.PROFILE_SESSIONS.get(
        env.PROFILE_SESSIONS.idFromName(clinicAccountUid)
      );

      const sessionResponse = await sessionStub.fetch(
        "https://profile-session/validate",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            sessionId,
            profileId,
            clinicId,
            role: "doctor",
          }),
        }
      );

      if (!sessionResponse.ok) {
        return Response.json(
          { error: "Doctor profile session is no longer active." },
          { status: 401 }
        );
      }

      // Verify the shared clinic account.
      const clinicAccount = await getFirestoreDocumentAsAdmin(
        `users/${clinicAccountUid}`,
        env
      );

      const accountFields = clinicAccount?.fields ?? {};

      if (
        accountFields.role?.stringValue !== "clinic_staff" ||
        accountFields.status?.stringValue !== "active" ||
        accountFields.clinicId?.stringValue !== clinicId
      ) {
        return Response.json(
          { error: "Clinic staff account is not authorized." },
          { status: 403 }
        );
      }

      // Verify the individual staff profile.
      const staffProfile = await getFirestoreDocumentAsAdmin(
        `staffProfiles/${profileId}`,
        env
      );

      const profileFields = staffProfile?.fields ?? {};

      if (
        profileFields.clinicId?.stringValue !== clinicId ||
        profileFields.status?.stringValue !== "active" ||
        profileFields.role?.stringValue !== "doctor"
      ) {
        return Response.json(
          { error: "Doctor profile is not authorized." },
          { status: 403 }
        );
      }

      // Verify online consultation eligibility.
      const doctor = await getFirestoreDocumentAsAdmin(
        `doctors/${profileId}`,
        env
      );

      const doctorFields = doctor?.fields ?? {};

      if (
        doctorFields.clinicId?.stringValue !== clinicId ||
        doctorFields.active?.booleanValue !== true ||
        doctorFields.supportsOnline?.booleanValue !== true
      ) {
        return Response.json(
          { error: "Doctor is not authorized for online consultations." },
          { status: 403 }
        );
      }

      participantIdentity = profileId;
      participantName =
        profileFields.name?.stringValue ??
        doctorFields.name?.stringValue ??
        "Doctor";
    }

    // 6. Check the consultation room status.
    const roomName = `${APPOINTMENT_PREFIX}${appointmentId}`;

    const durableObjectId =
      env.ROOM_STATE.idFromName(appointmentId);

    const roomState = env.ROOM_STATE.get(durableObjectId);

    const roomStatusResponse = await roomState.fetch(
      "https://room-state.internal/status",
      { method: "GET" }
    );

    if (!roomStatusResponse.ok) {
      throw new Error("Unable to check consultation room status.");
    }

    const roomStatus = await roomStatusResponse.json() as {
      roomClosed: boolean;
      instantMeetingEnabled: boolean;
    };

    if (roomStatus.roomClosed) {
      return Response.json(
        { error: "This consultation room has been closed." },
        { status: 403 }
      );
    }

    if (!roomStatus.instantMeetingEnabled) {
      return Response.json(
        { error: "The doctor has not started the consultation yet." },
        { status: 403 }
      );
    }

    // 7. Validate LiveKit configuration.
    if (
      typeof env.LIVEKIT_URL !== "string" ||
      !env.LIVEKIT_URL.startsWith("wss://")
    ) {
      console.error("LiveKit URL configuration is missing or invalid.");

      return Response.json(
        { error: "LiveKit server configuration is invalid." },
        { status: 500 }
      );
    }

    // 8. Generate the participant's LiveKit access token.
    const accessToken = new AccessToken(
      env.LIVEKIT_API_KEY,
      env.LIVEKIT_API_SECRET,
      {
        identity: participantIdentity,
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

    const livekitToken = await accessToken.toJwt();

    return Response.json({
      serverUrl: env.LIVEKIT_URL,
      roomName,
      token: livekitToken,
    });
  } catch (error) {
    console.error("Consultation token error:", error);

    return Response.json(
      { error: "Unable to prepare the consultation room." },
      { status: 500 }
    );
  }
}


async function handleGetConsultationMessages(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    // 1. Verify the authorization token.
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    let patientUid: string | null = null;
    let clinicAccountUid: string | null = null;
    let profileId: string | null = null;
    let clinicId: string | null = null;
    let sessionId: string | null = null;

    // 2. Try doctor profile-session authentication.
    try {
      const { payload } = await jwtVerify(
        token,
        new TextEncoder().encode(env.PROFILE_SESSION_SECRET),
        {
          issuer: "bcksnap-backend",
          audience: "bcksnap-staff",
          algorithms: ["HS256"],
        }
      );

      if (
        typeof payload.clinicAccountUid === "string" &&
        typeof payload.profileId === "string" &&
        typeof payload.clinicId === "string" &&
        typeof payload.sessionId === "string" &&
        payload.role === "doctor"
      ) {
        clinicAccountUid = payload.clinicAccountUid;
        profileId = payload.profileId;
        clinicId = payload.clinicId;
        sessionId = payload.sessionId;
      }
    } catch (_) {
      // Try Firebase patient authentication instead.
    }

    // 3. Verify patient Firebase authentication if no doctor profile was found.
    if (!profileId) {
      try {
        const { payload } = await jwtVerify(
          token,
          FIREBASE_JWKS,
          {
            issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
            audience: FIREBASE_PROJECT_ID,
            algorithms: ["RS256"],
          }
        );

        if (typeof payload.sub !== "string") {
          return Response.json(
            { error: "Invalid user identity." },
            { status: 401 }
          );
        }

        patientUid = payload.sub;
      } catch (_) {
        return Response.json(
          { error: "Invalid authentication token." },
          { status: 401 }
        );
      }
    }

    // 4. Validate the appointment ID.
    const url = new URL(request.url);
    const appointmentId = url.searchParams.get("appointmentId");

    if (
      !appointmentId ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "A valid appointment ID is required." },
        { status: 400 }
      );
    }

    // 5. Retrieve appointment using Admin credentials.
    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const fields = appointment.fields ?? {};

    if (
      fields.status?.stringValue !== "approved" ||
      fields.mode?.stringValue !== "online" ||
      fields.isDemo?.booleanValue === true
    ) {
      return Response.json(
        { error: "This appointment is not eligible for consultation messaging." },
        { status: 403 }
      );
    }

    // 6. Verify patient or doctor access.
    if (patientUid !== null) {
      if (fields.userId?.stringValue !== patientUid) {
        return Response.json(
          { error: "You are not authorized to access these messages." },
          { status: 403 }
        );
      }

      const patient = await getFirestoreDocumentAsAdmin(
        `users/${patientUid}`,
        env
      );

      if (
        patient?.fields?.role?.stringValue !== "user" ||
        patient?.fields?.status?.stringValue !== "active"
      ) {
        return Response.json(
          { error: "Patient account is not authorized." },
          { status: 403 }
        );
      }
    } else {
      if (
        !clinicAccountUid ||
        !profileId ||
        !clinicId ||
        !sessionId ||
        fields.doctorId?.stringValue !== profileId ||
        fields.clinicId?.stringValue !== clinicId
      ) {
        return Response.json(
          { error: "You are not authorized to access these messages." },
          { status: 403 }
        );
      }

      // Validate active profile session.
      const sessionStub = env.PROFILE_SESSIONS.get(
        env.PROFILE_SESSIONS.idFromName(clinicAccountUid)
      );

      const sessionResponse = await sessionStub.fetch(
        "https://profile-session/validate",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            sessionId,
            profileId,
            clinicId,
            role: "doctor",
          }),
        }
      );

      if (!sessionResponse.ok) {
        return Response.json(
          { error: "Doctor profile session is no longer active." },
          { status: 401 }
        );
      }

      const clinicAccount = await getFirestoreDocumentAsAdmin(
        `users/${clinicAccountUid}`,
        env
      );

      const accountFields = clinicAccount?.fields ?? {};

      if (
        accountFields.role?.stringValue !== "clinic_staff" ||
        accountFields.status?.stringValue !== "active" ||
        accountFields.clinicId?.stringValue !== clinicId
      ) {
        return Response.json(
          { error: "Clinic staff account is not authorized." },
          { status: 403 }
        );
      }

      const staffProfile = await getFirestoreDocumentAsAdmin(
        `staffProfiles/${profileId}`,
        env
      );

      const profileFields = staffProfile?.fields ?? {};

      if (
        profileFields.clinicId?.stringValue !== clinicId ||
        profileFields.status?.stringValue !== "active" ||
        profileFields.role?.stringValue !== "doctor"
      ) {
        return Response.json(
          { error: "Doctor profile is not authorized." },
          { status: 403 }
        );
      }
    }

    // 7. Retrieve messages from the existing subcollection.
    const accessToken = await getGoogleAccessToken(env);

    const collectionPath =
      `appointments/${appointmentId}/chatMessages`;

    const encodedPath = collectionPath
      .split("/")
      .map(encodeURIComponent)
      .join("/");

    const messagesResponse = await fetch(
      `https://firestore.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/databases/(default)/documents/${encodedPath}?pageSize=100&orderBy=createdAt`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${accessToken}`,
        },
      }
    );

    if (!messagesResponse.ok) {
      throw new Error(
        `Firestore message read failed with status ${messagesResponse.status}.`
      );
    }

    const messagesData = await messagesResponse.json() as {
      documents?: Array<{
        name: string;
        fields?: Record<string, any>;
      }>;
    };

    const messages = (messagesData.documents ?? []).map((document) => {
      const messageFields = document.fields ?? {};
      const nameParts = document.name.split("/");

      return {
        id: nameParts[nameParts.length - 1],
        senderId: messageFields.senderId?.stringValue ?? "",
        senderRole: messageFields.senderRole?.stringValue ?? "",
        text: messageFields.text?.stringValue ?? "",
        createdAt:
          messageFields.createdAt?.timestampValue ?? null,
      };
    });

    messages.sort((a, b) => {
      return (a.createdAt ?? "").localeCompare(b.createdAt ?? "");
    });

    return Response.json({
      success: true,
      messages,
    });
  } catch (error) {
    console.error("Get consultation messages error:", error);

    return Response.json(
      { error: "Unable to load consultation messages." },
      { status: 500 }
    );
  }
}


async function handleSendConsultationMessage(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Authentication required." },
        { status: 401 }
      );
    }

    let senderId: string;
    let senderRole: "patient" | "doctor";

    // Verify doctor profile-session authentication first.
    try {
      const { payload } = await jwtVerify(
        token,
        new TextEncoder().encode(env.PROFILE_SESSION_SECRET),
        {
          issuer: "bcksnap-backend",
          audience: "bcksnap-staff",
          algorithms: ["HS256"],
        }
      );

      if (
        typeof payload.clinicAccountUid !== "string" ||
        typeof payload.profileId !== "string" ||
        typeof payload.clinicId !== "string" ||
        typeof payload.sessionId !== "string" ||
        payload.role !== "doctor"
      ) {
        throw new Error("Invalid doctor profile.");
      }

      const clinicAccountUid = payload.clinicAccountUid;
      const profileId = payload.profileId;
      const clinicId = payload.clinicId;
      const sessionId = payload.sessionId;

      const sessionStub = env.PROFILE_SESSIONS.get(
        env.PROFILE_SESSIONS.idFromName(clinicAccountUid)
      );

      const sessionResponse = await sessionStub.fetch(
        "https://profile-session/validate",
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            sessionId,
            profileId,
            clinicId,
            role: "doctor",
          }),
        }
      );

      if (!sessionResponse.ok) {
        return Response.json(
          { error: "Doctor profile session is no longer active." },
          { status: 401 }
        );
      }

      const clinicAccount = await getFirestoreDocumentAsAdmin(
        `users/${clinicAccountUid}`,
        env
      );

      const accountFields = clinicAccount?.fields ?? {};

      if (
        accountFields.role?.stringValue !== "clinic_staff" ||
        accountFields.status?.stringValue !== "active" ||
        accountFields.clinicId?.stringValue !== clinicId
      ) {
        return Response.json(
          { error: "Clinic staff account is not authorized." },
          { status: 403 }
        );
      }

      const staffProfile = await getFirestoreDocumentAsAdmin(
        `staffProfiles/${profileId}`,
        env
      );

      const profileFields = staffProfile?.fields ?? {};

      if (
        profileFields.clinicId?.stringValue !== clinicId ||
        profileFields.status?.stringValue !== "active" ||
        profileFields.role?.stringValue !== "doctor"
      ) {
        return Response.json(
          { error: "Doctor profile is not authorized." },
          { status: 403 }
        );
      }

      senderId = profileId;
      senderRole = "doctor";
    } catch (_) {
      // Try Firebase patient authentication.
      try {
        const { payload } = await jwtVerify(
          token,
          FIREBASE_JWKS,
          {
            issuer: `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`,
            audience: FIREBASE_PROJECT_ID,
            algorithms: ["RS256"],
          }
        );

        if (typeof payload.sub !== "string") {
          return Response.json(
            { error: "Invalid user identity." },
            { status: 401 }
          );
        }

        senderId = payload.sub;
        senderRole = "patient";
      } catch (_) {
        return Response.json(
          { error: "Invalid authentication token." },
          { status: 401 }
        );
      }
    }

    const body = await request.json() as {
      appointmentId?: unknown;
      text?: unknown;
    };

    const appointmentId = body.appointmentId;
    const message = typeof body.text === "string"
      ? body.text.trim()
      : "";

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "A valid appointment ID is required." },
        { status: 400 }
      );
    }

    if (!message) {
      return Response.json(
        { error: "Message cannot be empty." },
        { status: 422 }
      );
    }

    if (message.length > 4000) {
      return Response.json(
        { error: "Message cannot exceed 4000 characters." },
        { status: 422 }
      );
    }

    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const fields = appointment.fields ?? {};

    if (
      fields.status?.stringValue !== "approved" ||
      fields.mode?.stringValue !== "online" ||
      fields.isDemo?.booleanValue === true
    ) {
      return Response.json(
        { error: "This appointment is not eligible for consultation messaging." },
        { status: 403 }
      );
    }

    if (senderRole === "patient") {
      if (fields.userId?.stringValue !== senderId) {
        return Response.json(
          { error: "You are not authorized to send messages to this appointment." },
          { status: 403 }
        );
      }

      const patient = await getFirestoreDocumentAsAdmin(
        `users/${senderId}`,
        env
      );

      if (
        patient?.fields?.role?.stringValue !== "user" ||
        patient?.fields?.status?.stringValue !== "active"
      ) {
        return Response.json(
          { error: "Patient account is not authorized." },
          { status: 403 }
        );
      }
    } else {
      if (
        fields.doctorId?.stringValue !== senderId
      ) {
        return Response.json(
          { error: "Only the assigned doctor can send messages." },
          { status: 403 }
        );
      }
    }

    const now = new Date().toISOString();

    const createdDocument = await createFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      "chatMessages",
      {
        senderId: { stringValue: senderId },
        senderRole: { stringValue: senderRole },
        text: { stringValue: message },
        createdAt: { timestampValue: now },
      },
      env
    );

    const nameParts = String(createdDocument.name ?? "").split("/");
    const messageId = nameParts[nameParts.length - 1];

    return Response.json({
      success: true,
      message: {
        id: messageId,
        senderId,
        senderRole,
        text: message,
        createdAt: now,
      },
    });
  } catch (error) {
    console.error("Send consultation message error:", error);

    return Response.json(
      { error: "Unable to send consultation message." },
      { status: 500 }
    );
  }
}


async function handleInstantMeetingStart(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    // 1. Verify the selected doctor profile session.
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Profile session required." },
        { status: 401 }
      );
    }

    const { payload } = await jwtVerify(
      token,
      new TextEncoder().encode(env.PROFILE_SESSION_SECRET),
      {
        issuer: "bcksnap-backend",
        audience: "bcksnap-staff",
        algorithms: ["HS256"],
      }
    );

    const clinicAccountUid = payload.clinicAccountUid;
    const profileId = payload.profileId;
    const clinicId = payload.clinicId;
    const role = payload.role;
    const sessionId = payload.sessionId;

    if (
      typeof clinicAccountUid !== "string" ||
      typeof profileId !== "string" ||
      typeof clinicId !== "string" ||
      typeof sessionId !== "string" ||
      role !== "doctor"
    ) {
      return Response.json(
        { error: "Only an active doctor profile can start an instant meeting." },
        { status: 403 }
      );
    }

    // 2. Validate that the profile session is still active.
    const sessionStub = env.PROFILE_SESSIONS.get(
      env.PROFILE_SESSIONS.idFromName(clinicAccountUid)
    );

    const sessionResponse = await sessionStub.fetch(
      "https://profile-session/validate",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sessionId,
          profileId,
          clinicId,
          role,
        }),
      }
    );

    if (!sessionResponse.ok) {
      return Response.json(
        { error: "Profile session is no longer active." },
        { status: 401 }
      );
    }

    // 3. Verify the shared clinic account.
    const clinicAccount = await getFirestoreDocumentAsAdmin(
      `users/${clinicAccountUid}`,
      env
    );

    const accountFields = clinicAccount?.fields ?? {};

    if (
      accountFields.role?.stringValue !== "clinic_staff" ||
      accountFields.status?.stringValue !== "active" ||
      accountFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "Clinic staff account is not authorized." },
        { status: 403 }
      );
    }

    // 4. Verify the selected doctor profile.
    const staffProfile = await getFirestoreDocumentAsAdmin(
      `staffProfiles/${profileId}`,
      env
    );

    const profileFields = staffProfile?.fields ?? {};

    if (
      profileFields.clinicId?.stringValue !== clinicId ||
      profileFields.status?.stringValue !== "active" ||
      profileFields.role?.stringValue !== "doctor"
    ) {
      return Response.json(
        { error: "Doctor profile is not authorized." },
        { status: 403 }
      );
    }

    const doctor = await getFirestoreDocumentAsAdmin(
      `doctors/${profileId}`,
      env
    );

    const doctorFields = doctor?.fields ?? {};

    if (
      doctorFields.clinicId?.stringValue !== clinicId ||
      doctorFields.active?.booleanValue !== true ||
      doctorFields.supportsOnline?.booleanValue !== true
    ) {
      return Response.json(
        { error: "Doctor is not authorized for online consultations." },
        { status: 403 }
      );
    }

    // 5. Validate the appointment ID.
    const body = await request.json() as {
      appointmentId?: unknown;
    };

    const appointmentId = body.appointmentId;

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "A valid appointment ID is required." },
        { status: 400 }
      );
    }

    // 6. Retrieve and verify the appointment.
    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const appointmentFields = appointment.fields ?? {};

    if (
      appointmentFields.doctorId?.stringValue !== profileId ||
      appointmentFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "Only the assigned doctor can start this instant meeting." },
        { status: 403 }
      );
    }

    if (
      appointmentFields.status?.stringValue !== "approved" ||
      appointmentFields.mode?.stringValue !== "online" ||
      appointmentFields.isDemo?.booleanValue === true
    ) {
      return Response.json(
        { error: "This appointment is not eligible for an instant meeting." },
        { status: 403 }
      );
    }

    // 7. Prepare the appointment's consultation room.
    const roomName = `${APPOINTMENT_PREFIX}${appointmentId}`;

    const durableObjectId =
      env.ROOM_STATE.idFromName(appointmentId);

    const roomState = env.ROOM_STATE.get(durableObjectId);

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
      const errorData = await roomSetupResponse.json() as {
        error?: string;
      };

      return Response.json(
        {
          error: errorData.error ??
            "Unable to prepare the consultation room.",
        },
        { status: roomSetupResponse.status }
      );
    }

    // 8. Enable instant meeting access.
    const instantResponse = await roomState.fetch(
      "https://room-state.internal/enable-instant",
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

    if (!instantResponse.ok) {
      const errorData = await instantResponse.json() as {
        error?: string;
      };

      return Response.json(
        {
          error: errorData.error ??
            "Unable to activate instant meeting.",
        },
        { status: instantResponse.status }
      );
    }

    return Response.json({
      success: true,
      message: "Instant meeting started successfully.",
      appointmentId,
      roomName,
    });
  } catch (error) {
    console.error("Instant meeting start error:", error);

    return Response.json(
      { error: "Unable to start the instant meeting." },
      { status: 500 }
    );
  }
}


async function handleConsultationEnd(
  request: Request,
  env: Env
): Promise<Response> {
  try {
    // 1. Verify the selected doctor profile session.
    const authorization = request.headers.get("Authorization") ?? "";
    const token = authorization.startsWith("Bearer ")
      ? authorization.slice(7)
      : "";

    if (!token) {
      return Response.json(
        { error: "Profile session required." },
        { status: 401 }
      );
    }

    const { payload } = await jwtVerify(
      token,
      new TextEncoder().encode(env.PROFILE_SESSION_SECRET),
      {
        issuer: "bcksnap-backend",
        audience: "bcksnap-staff",
        algorithms: ["HS256"],
      }
    );

    const clinicAccountUid = payload.clinicAccountUid;
    const profileId = payload.profileId;
    const clinicId = payload.clinicId;
    const role = payload.role;
    const sessionId = payload.sessionId;

    if (
      typeof clinicAccountUid !== "string" ||
      typeof profileId !== "string" ||
      typeof clinicId !== "string" ||
      typeof sessionId !== "string" ||
      role !== "doctor"
    ) {
      return Response.json(
        { error: "Only an active doctor profile can end this consultation." },
        { status: 403 }
      );
    }

    // 2. Validate that the profile session is still active.
    const sessionStub = env.PROFILE_SESSIONS.get(
      env.PROFILE_SESSIONS.idFromName(clinicAccountUid)
    );

    const sessionResponse = await sessionStub.fetch(
      "https://profile-session/validate",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          sessionId,
          profileId,
          clinicId,
          role,
        }),
      }
    );

    if (!sessionResponse.ok) {
      return Response.json(
        { error: "Profile session is no longer active." },
        { status: 401 }
      );
    }

    // 3. Verify the shared clinic account.
    const clinicAccount = await getFirestoreDocumentAsAdmin(
      `users/${clinicAccountUid}`,
      env
    );

    const accountFields = clinicAccount?.fields ?? {};

    if (
      accountFields.role?.stringValue !== "clinic_staff" ||
      accountFields.status?.stringValue !== "active" ||
      accountFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "Clinic staff account is not authorized." },
        { status: 403 }
      );
    }

    // 4. Verify the selected doctor profile.
    const staffProfile = await getFirestoreDocumentAsAdmin(
      `staffProfiles/${profileId}`,
      env
    );

    const profileFields = staffProfile?.fields ?? {};

    if (
      profileFields.clinicId?.stringValue !== clinicId ||
      profileFields.status?.stringValue !== "active" ||
      profileFields.role?.stringValue !== "doctor"
    ) {
      return Response.json(
        { error: "Doctor profile is not authorized." },
        { status: 403 }
      );
    }

    // 5. Verify the doctor's online consultation eligibility.
    const doctor = await getFirestoreDocumentAsAdmin(
      `doctors/${profileId}`,
      env
    );

    const doctorFields = doctor?.fields ?? {};

    if (
      doctorFields.clinicId?.stringValue !== clinicId ||
      doctorFields.active?.booleanValue !== true ||
      doctorFields.supportsOnline?.booleanValue !== true
    ) {
      return Response.json(
        { error: "Doctor is not authorized for online consultations." },
        { status: 403 }
      );
    }

    // 6. Validate the appointment ID.
    const body = await request.json() as {
      appointmentId?: unknown;
    };

    const appointmentId = body.appointmentId;

    if (
      typeof appointmentId !== "string" ||
      !/^[A-Za-z0-9_-]{1,128}$/.test(appointmentId)
    ) {
      return Response.json(
        { error: "A valid appointment ID is required." },
        { status: 400 }
      );
    }

    // 7. Retrieve and verify the appointment.
    const appointment = await getFirestoreDocumentAsAdmin(
      `appointments/${appointmentId}`,
      env
    );

    if (!appointment) {
      return Response.json(
        { error: "Appointment not found." },
        { status: 404 }
      );
    }

    const appointmentFields = appointment.fields ?? {};

    if (
      appointmentFields.doctorId?.stringValue !== profileId ||
      appointmentFields.clinicId?.stringValue !== clinicId
    ) {
      return Response.json(
        { error: "Only the assigned doctor can end this consultation." },
        { status: 403 }
      );
    }

    if (
      appointmentFields.status?.stringValue !== "approved" ||
      appointmentFields.mode?.stringValue !== "online" ||
      appointmentFields.isDemo?.booleanValue === true
    ) {
      return Response.json(
        { error: "This appointment is not eligible for consultation closure." },
        { status: 403 }
      );
    }

    // 8. Close the appointment's LiveKit room.
    const roomName = `${APPOINTMENT_PREFIX}${appointmentId}`;

    const durableObjectId =
      env.ROOM_STATE.idFromName(appointmentId);

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
        {
          error: endResult.error ??
            "Unable to end the consultation.",
        },
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