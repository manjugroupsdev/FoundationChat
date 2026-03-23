# MMS 2.0 — API Documentation

> **Base URL:** `https://mms20-core-api.azurewebsites.net/api`
>
> **Protocol:** All endpoints use `POST /api` with a JSON envelope.
>
> **Last verified:** 2026-03-21 on production Azure

---

## Request & Response Format

Every API call follows this envelope pattern:

### Request

```json
POST /api
Content-Type: application/json

{
  "namespace": "<module>",
  "apiName": "<endpointName>",
  "data": { ... },
  "auth": "{\"userId\": 123}"
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `namespace` | string | Yes | Module name (e.g., `auth`, `marketing`, `hr`) |
| `apiName` | string | Yes | Endpoint name (camelCase) |
| `data` | object | Yes | Endpoint-specific input payload |
| `auth` | string | No | JSON string with `{"userId": <id>}` for authenticated requests |

### Response

```json
// Success
{ "status": "ok", "data": { ... } }

// Error
{ "status": "error", "message": "description of error" }
```

---

## 1. Authentication

### 1.1 Login (Username/Password)

**For:** Admin web app login

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "auth",
    "apiName": "login",
    "data": {
      "userName": "admin",
      "password": "yourpassword"
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `userName` | string | Yes | Username |
| `password` | string | Yes | Password (case-sensitive) |

**Response (Success):**

```json
{
  "status": "ok",
  "data": {
    "userId": 1,
    "userName": "admin",
    "fullName": "Administrator",
    "roleId": 1,
    "roleName": "Super Admin",
    "roleLevel": 1,
    "isAdmin": true,
    "branchId": 1,
    "defaultMenuId": 100,
    "recordAccessRights": "all",
    "downloadAccessRights": "enabled"
  }
}
```

**Errors:**

| Error | Cause |
|-------|-------|
| `userName and password are required` | Empty credentials |
| `invalid username or password` | Wrong credentials |

---

### 1.2 OTP Send (Mobile)

**For:** Mobile app login — Step 1

Sends a 4-digit OTP via Airtel IQ SMS to the given mobile number. OTP is valid for **10 minutes** with max **5 verification attempts**.

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "auth",
    "apiName": "otpSend",
    "data": {
      "mobileNumber": "6369487527"
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mobileNumber` | string | Yes | 10-digit Indian mobile (with or without +91 prefix) |

**Response (Success):**

```json
{
  "status": "ok",
  "data": {
    "sent": true,
    "message": "OTP sent successfully"
  }
}
```

**Errors:**

| Error | Cause |
|-------|-------|
| `mobileNumber is required` | Empty mobile number |
| `invalid mobile number` | Less than 10 digits |
| `OTP service is not configured` | Airtel SMS env vars missing on server |

**Notes:**
- Calling again for the same number generates a **new OTP** (old one is replaced)
- SMS is delivered via Airtel IQ prepaid SMS API with DLT template compliance

---

### 1.3 OTP Verify (Mobile)

**For:** Mobile app login — Step 2

Verifies the OTP and returns full user session if the mobile number matches an active user in the database.

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "auth",
    "apiName": "otpVerify",
    "data": {
      "mobileNumber": "6369487527",
      "otp": "1234"
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mobileNumber` | string | Yes | Same mobile number used in otpSend |
| `otp` | string | Yes | 4-digit OTP received via SMS |

**Response (Success — user found):**

```json
{
  "status": "ok",
  "data": {
    "verified": true,
    "userId": 1303,
    "userName": "RAJ KUMAR.M",
    "fullName": "Raj Kumar M",
    "roleId": 3,
    "roleName": "Sales Executive",
    "isAdmin": false,
    "branchId": 1,
    "message": "OTP verified, login successful"
  }
}
```

**Response (Wrong OTP):**

```json
{
  "status": "ok",
  "data": {
    "verified": false,
    "userId": 0,
    "userName": "",
    "fullName": "",
    "roleId": 0,
    "roleName": "",
    "isAdmin": false,
    "branchId": 0,
    "message": "invalid OTP (4 attempts remaining)"
  }
}
```

**Response (OTP verified but no user):**

```json
{
  "status": "ok",
  "data": {
    "verified": true,
    "userId": 0,
    "message": "OTP verified but no user found with this mobile number"
  }
}
```

**Errors:**

| Message | Cause |
|---------|-------|
| `no OTP sent to this number` | otpSend not called first |
| `OTP expired` | Over 10 minutes since otpSend |
| `too many attempts, OTP invalidated` | 5+ wrong attempts |
| `OTP already used` | Already verified once |

**User Lookup:** Searches `UM_Users.MobileNo`, `t_HR_Employee.PersonalMobileNo`, and `t_HR_Employee.OfficeMobileNo`.

---

## 2. Site Visit GPS Tracking

### 2.1 List GPS Site Visits

**For:** View all field staff GPS trips with filtering

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitGPSList",
    "data": {
      "search": "",
      "limit": 50,
      "userId": 0,
      "mode": "all"
    }
  }'
```

**Input:**

| Field | Type | Required | Default | Description |
|-------|------|----------|---------|-------------|
| `search` | string | No | `""` | Search by employee name, ref number, or remarks |
| `limit` | int | No | `200` | Max records to return |
| `userId` | int64 | No | `0` | Filter by specific user (0 = all users) |
| `mode` | string | No | `"all"` | `"all"` = all records, `"pending"` = unapproved only |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "siteVisitGPSId": 180736,
        "refNo": "40743",
        "purpose": "Others",
        "remarks": "cp kk nager",
        "startingDateAndTime": "2025-12-13T17:18:04Z",
        "endingDateAndTime": "2025-12-13T17:18:28Z",
        "isApproved": false,
        "approvalBy": 0,
        "reason": "",
        "userId": 1303,
        "userName": "RAJ KUMAR.M",
        "roleId": 3,
        "startingLocation": "13.0367350, 80.1976079",
        "endingLocation": "13.0367917, 80.1976900",
        "noOfLocation": 0,
        "noOfImages": 0,
        "totalDuration": "00:00:23",
        "createdDateAndTime": "2025-12-13T17:18:04Z"
      }
    ]
  }
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `siteVisitGPSId` | int64 | Unique GPS session ID |
| `refNo` | string | Reference number |
| `purpose` | string | Visit purpose (e.g., "Site Visit", "Others") |
| `remarks` | string | User-entered remarks |
| `startingDateAndTime` | ISO 8601 | When the session started |
| `endingDateAndTime` | ISO 8601 | When the session ended (null if still active) |
| `isApproved` | bool | Whether manager approved this trip |
| `userId` | int64 | Field staff user ID |
| `userName` | string | Field staff name |
| `startingLocation` | string | "lat, lng" of start point |
| `endingLocation` | string | "lat, lng" of end point |
| `noOfLocation` | int | Number of GPS waypoints recorded |
| `noOfImages` | int | Number of photos attached |
| `totalDuration` | string | "HH:MM:SS" duration |

---

### 2.2 GPS Trip Detail (Waypoints)

**For:** Get full GPS path for a single trip — **use this to draw the route on a map**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitGPSDetail",
    "data": {
      "siteVisitGPSId": 180735
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `siteVisitGPSId` | int64 | Yes | GPS session ID from siteVisitGPSList |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "siteVisitGPSId": 180735,
    "refNo": "40742",
    "userName": "RAJ KUMAR.M",
    "purpose": "Others",
    "startingDateAndTime": "2025-12-13T17:18:03Z",
    "endingDateAndTime": "2025-12-13T17:18:23Z",
    "totalDuration": "00:00:20",
    "waypoints": [
      {
        "latitude": 13.0367917,
        "longitude": 80.19769,
        "isManuallyCaptured": false,
        "description": ""
      }
    ]
  }
}
```

**Waypoint Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `latitude` | float64 | GPS latitude |
| `longitude` | float64 | GPS longitude |
| `isManuallyCaptured` | bool | true = user manually added this point |
| `description` | string | Optional description for this waypoint |

---

### 2.3 GPS Day Map (All Users)

**For:** Plot all GPS activity for a given date on a map — shows all users' waypoints and trip segments

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitGPSDayMap",
    "data": {
      "date": "2025-12-13",
      "userId": 1303
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `date` | string | Yes | Date in `YYYY-MM-DD` format |
| `userId` | int64 | No | Filter to specific user (0 = all users) |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "date": "2025-12-13",
    "users": [
      {
        "userId": 1303,
        "userName": "RAJ KUMAR.M",
        "recordCount": 6,
        "totalPoints": 5,
        "totalDuration": "00:01:40",
        "firstStart": "2025-12-13T14:22:37Z",
        "lastEnd": "2025-12-13T17:18:28Z",
        "purposes": "Others"
      }
    ],
    "waypoints": [
      {
        "lat": 13.0359317,
        "lng": 80.2227833,
        "manual": false,
        "time": "2025-12-13T14:22:41Z",
        "gpsId": 180722
      },
      {
        "lat": 13.0278333,
        "lng": 80.219375,
        "manual": false,
        "time": "2025-12-13T14:46:47Z",
        "gpsId": 180724
      },
      {
        "lat": 13.0190533,
        "lng": 80.203645,
        "manual": false,
        "time": "2025-12-13T15:42:16Z",
        "gpsId": 180729
      }
    ],
    "segments": [
      {
        "gpsId": 180722,
        "purpose": "Others",
        "startTime": "2025-12-13T14:22:37Z",
        "endTime": "2025-12-13T14:22:48Z"
      },
      {
        "gpsId": 180724,
        "purpose": "Others",
        "startTime": "2025-12-13T14:46:40Z",
        "endTime": "2025-12-13T14:47:09Z"
      }
    ]
  }
}
```

**Response Fields:**

| Field | Type | Description |
|-------|------|-------------|
| `users` | array | Summary per user for that day |
| `waypoints` | array | All GPS points (for map markers/polyline) |
| `waypoints[].lat` | float64 | Latitude |
| `waypoints[].lng` | float64 | Longitude |
| `waypoints[].time` | ISO 8601 | When this point was recorded |
| `waypoints[].gpsId` | int64 | Which GPS session this belongs to |
| `segments` | array | Trip segments (for grouping waypoints by visit) |

**Usage for map:** Plot `waypoints` as markers, connect them with a polyline ordered by `time`. Use `segments` to color-code different trips.

---

### 2.4 OD (Origin-Destination) Approval

**For:** Manager approves or rejects a field staff's GPS trip

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "odApprovalSave",
    "data": {
      "siteVisitGPSId": 180735,
      "actorUserId": 1,
      "isApproved": true,
      "reason": "Route verified"
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `siteVisitGPSId` | int64 | Yes | GPS session to approve/reject |
| `actorUserId` | int64 | Yes | Manager's user ID (from login session) |
| `isApproved` | bool | Yes | `true` = approve, `false` = reject |
| `reason` | string | No | Reason for approval/rejection |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "saved": true
  }
}
```

---

## 3. Site Visit Travel Log

### 3.1 Travel List

**For:** Vehicle travel report — KM tracking, driver info, project details

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "svTravelList",
    "data": {
      "search": "",
      "limit": 50,
      "fromDate": "2025-12-01",
      "toDate": "2025-12-31",
      "projectName": "",
      "driverName": "",
      "vehicleNumber": ""
    }
  }'
```

**Input:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `search` | string | No | Free-text search |
| `limit` | int | No | Max records (default: 200) |
| `fromDate` | string | No | Start date filter `YYYY-MM-DD` |
| `toDate` | string | No | End date filter `YYYY-MM-DD` |
| `projectName` | string | No | Filter by project name |
| `driverName` | string | No | Filter by driver name |
| `vehicleNumber` | string | No | Filter by vehicle number |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "siteVisitDate": "2025-12-15T00:00:00Z",
        "nameOfProject": "Luxury X - Grandeur Bungalows",
        "clientName": "Ranjit zachariah",
        "pickupLocation": "nazarethpet",
        "pickupTime": "11:00 am",
        "driverName": "",
        "driverContactNumber": "",
        "vehicleNumber": "",
        "openingKM": 0,
        "closingKM": 0,
        "totalKM": 0,
        "siteIncharge": "NIRMALRAJ.C",
        "hodName": "NIRMALRAJ.C"
      }
    ]
  }
}
```

---

## 4. Mobile App Integration Guide

### Complete Login Flow

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  Mobile App  │     │   Core API       │     │  Airtel SMS  │
│              │     │                  │     │              │
│ Enter mobile ├────>│ auth/otpSend     ├────>│ Send 4-digit │
│   number     │     │                  │     │ OTP via SMS  │
│              │<────┤ {sent: true}     │     │              │
│              │     │                  │     │              │
│ Enter OTP    ├────>│ auth/otpVerify   │     │              │
│              │     │ Check OTP +      │     │              │
│              │<────┤ Lookup user by   │     │              │
│              │     │ mobile in DB     │     │              │
│ Store userId │     │                  │     │              │
│ + session    │     │ Returns: userId, │     │              │
│              │     │ userName, roleId │     │              │
└──────────────┘     └──────────────────┘     └──────────────┘
```

### GPS Tracking Flow (Read)

```
┌──────────────┐     ┌──────────────────┐
│  Admin App   │     │   Core API       │
│              │     │                  │
│ Select date  ├────>│ siteVisitGPS     │
│              │     │ DayMap           │
│              │<────┤ {waypoints,      │
│              │     │  segments}       │
│ Plot on map  │     │                  │
│              │     │                  │
│ Click trip   ├────>│ siteVisitGPS     │
│              │     │ Detail           │
│              │<────┤ {waypoints[]}    │
│ Show route   │     │                  │
│              │     │                  │
│ Approve/     ├────>│ odApproval       │
│ Reject       │     │ Save             │
│              │<────┤ {saved: true}    │
└──────────────┘     └──────────────────┘
```

---

## 5. Database Tables

| Table | Description |
|-------|-------------|
| `UM_Users` | User accounts (username, password, mobile, roleId) |
| `UM_ROLES` | Role definitions (role name, level, access rights) |
| `t_HR_Employee` | Employee master (personal/office mobile, department) |
| `t_SiteVisit_GPS` | GPS session headers (start/end time, purpose, approval) |
| `t_SiteVisit_GPS_Detail` | GPS waypoints (lat, lng, timestamp per session) |
| `t_SiteVisit_GPS_Images` | Photos attached to GPS sessions |
| `t_SiteVisit_Travel` | Vehicle travel log (KM, driver, vehicle) |

---

## 6. Environment Variables

### Core API Server

| Variable | Required | Description |
|----------|----------|-------------|
| `SQLSERVER_DSN` | Yes | SQL Server connection string |
| `APP_ENV` | No | `development` or `production` |
| `PORT` | No | HTTP port (default: 8080) |
| `AIRTEL_SMS_API_URL` | For OTP | Airtel IQ SMS API endpoint |
| `AIRTEL_SMS_CUSTOMER_ID` | For OTP | Airtel customer ID |
| `AIRTEL_SMS_ENTITY_ID` | For OTP | DLT entity ID |
| `AIRTEL_SMS_DLT_TEMPLATE_ID` | For OTP | DLT template ID |
| `AIRTEL_SMS_SOURCE_ADDRESS` | For OTP | SMS sender ID (default: MNJWLL) |

---

## 7. Error Handling

All errors follow the same format:

```json
{
  "status": "error",
  "message": "human-readable error description"
}
```

Common errors:

| HTTP | Error | Cause |
|------|-------|-------|
| 200 | `status: "error"` | Application-level error (bad input, not found, etc.) |
| 404 | Not found | Wrong URL (use POST /api only) |
| 500 | Internal server error | Server crash or DB connection issue |
