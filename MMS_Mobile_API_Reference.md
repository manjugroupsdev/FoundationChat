# MMS 2.0 — Mobile API Reference

**Base URL:** `https://mms20-core-api.azurewebsites.net/api`
**Method:** `POST` (all endpoints)
**Content-Type:** `application/json`

All requests use a unified envelope:

```json
{
  "namespace": "<module>",
  "apiName": "<endpoint>",
  "data": { ... }
}
```

All responses return:

```json
{
  "status": "ok",
  "data": { ... }
}
// or
{
  "status": "error",
  "message": "error description"
}
```

---

## 1. Authentication

### 1.1 Login with Username & Password

| Field | Value |
|-------|-------|
| namespace | `auth` |
| apiName | `login` |

**Request:**

```json
{
  "namespace": "auth",
  "apiName": "login",
  "data": {
    "userName": "admin",
    "password": "123"
  }
}
```

**Response:**

```json
{
  "status": "ok",
  "data": {
    "userId": 1,
    "userName": "admin",
    "fullName": "admin",
    "roleId": 1,
    "roleName": "Super Admin",
    "roleLevel": 8,
    "isAdmin": true,
    "branchId": 0,
    "defaultMenuId": 1,
    "recordAccessRights": "All Records",
    "downloadAccessRights": "Allowed"
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"auth","apiName":"login","data":{"userName":"admin","password":"123"}}'
```

---

### 1.2 OTP — Send OTP to Mobile

| Field | Value |
|-------|-------|
| namespace | `auth` |
| apiName | `otpSend` |

Sends a 4-digit OTP via Airtel IQ SMS. OTP is valid for **10 minutes** with max **5 attempts**.

**Request:**

```json
{
  "namespace": "auth",
  "apiName": "otpSend",
  "data": {
    "mobileNumber": "6369487527"
  }
}
```

**Response:**

```json
{
  "status": "ok",
  "data": {
    "sent": true,
    "message": "OTP sent successfully"
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"auth","apiName":"otpSend","data":{"mobileNumber":"6369487527"}}'
```

---

### 1.3 OTP — Verify OTP

| Field | Value |
|-------|-------|
| namespace | `auth` |
| apiName | `otpVerify` |

Verifies the OTP and returns user session if the mobile number matches a user in the system.

**Request:**

```json
{
  "namespace": "auth",
  "apiName": "otpVerify",
  "data": {
    "mobileNumber": "6369487527",
    "otp": "1234"
  }
}
```

**Success Response:**

```json
{
  "status": "ok",
  "data": {
    "verified": true,
    "userId": 1,
    "userName": "admin",
    "fullName": "admin",
    "roleId": 1,
    "roleName": "Super Admin",
    "isAdmin": true,
    "branchId": 0,
    "message": "OTP verified, login successful"
  }
}
```

**Failed Response:**

```json
{
  "status": "ok",
  "data": {
    "verified": false,
    "userId": 0,
    "message": "invalid OTP (4 attempts remaining)"
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"auth","apiName":"otpVerify","data":{"mobileNumber":"6369487527","otp":"1234"}}'
```

---

## 2. GPS Tracking — Post from Mobile

### Mobile Flow

```
App Opens → User logs in → Starts trip → GPS records waypoints → Ends trip → Upload photos
```

```
gpsSessionStart → gpsWaypointPost (every 30s) → gpsSessionEnd → gpsPhotoUpload
```

---

### 2.1 Start GPS Session

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `gpsSessionStart` |

Call this when the employee starts a field trip. Returns a `siteVisitGPSId` to use in all subsequent calls.

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "gpsSessionStart",
  "data": {
    "userId": 1,
    "purpose": "Client Visit - RE Nagar Porur",
    "remarks": "Meeting with client for site inspection",
    "startingLatitude": 13.034758,
    "startingLongitude": 80.155984,
    "callLogId": 0
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| userId | int | Yes | Logged-in user ID |
| purpose | string | Yes | Trip purpose (e.g., "Client Visit", "Site Inspection") |
| remarks | string | No | Additional notes |
| startingLatitude | float | Yes | GPS latitude at start |
| startingLongitude | float | Yes | GPS longitude at start |
| callLogId | int | No | Link to a call log entry (0 if none) |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "siteVisitGPSId": 180737,
    "refNo": "40744"
  }
}
```

> **Save `siteVisitGPSId` — you need it for all subsequent API calls in this session.**

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"gpsSessionStart","data":{"userId":1,"purpose":"Client Visit - RE Nagar Porur","remarks":"Meeting with client","startingLatitude":13.034758,"startingLongitude":80.155984,"callLogId":0}}'
```

---

### 2.2 Post GPS Waypoints (Batch)

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `gpsWaypointPost` |

Send GPS coordinates periodically (recommended: every 30 seconds) while the trip is active. Supports batch posting multiple waypoints at once.

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "gpsWaypointPost",
  "data": {
    "siteVisitGPSId": 180737,
    "userId": 1,
    "waypoints": [
      {
        "latitude": 13.034198,
        "longitude": 80.155658,
        "isManuallyCaptured": false,
        "description": "",
        "batteryPercentage": 85,
        "isGPSOn": true,
        "isWifiOn": true,
        "signalStrength": 4,
        "appVersion": "1.0.0",
        "locationName": ""
      },
      {
        "latitude": 13.033381,
        "longitude": 80.154999,
        "isManuallyCaptured": false,
        "description": "",
        "batteryPercentage": 84,
        "isGPSOn": true,
        "isWifiOn": true,
        "signalStrength": 4,
        "appVersion": "1.0.0",
        "locationName": ""
      },
      {
        "latitude": 13.032240,
        "longitude": 80.153990,
        "isManuallyCaptured": true,
        "description": "Checkpoint - CP kk nager",
        "batteryPercentage": 82,
        "isGPSOn": true,
        "isWifiOn": false,
        "signalStrength": 3,
        "appVersion": "1.0.0",
        "locationName": "CP KK Nagar"
      }
    ]
  }
}
```

| Waypoint Field | Type | Required | Description |
|----------------|------|----------|-------------|
| latitude | float | Yes | GPS latitude |
| longitude | float | Yes | GPS longitude |
| isManuallyCaptured | bool | No | `true` if user tapped "Mark Location" |
| description | string | No | Description for manual captures |
| batteryPercentage | int | No | Device battery level (0-100) |
| isGPSOn | bool | No | Is GPS enabled on device |
| isWifiOn | bool | No | Is WiFi enabled on device |
| signalStrength | int | No | Network signal strength (0-5) |
| appVersion | string | No | Mobile app version |
| locationName | string | No | Reverse-geocoded location name |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "savedCount": 5
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"gpsWaypointPost","data":{"siteVisitGPSId":180737,"userId":1,"waypoints":[{"latitude":13.034198,"longitude":80.155658,"isManuallyCaptured":false,"batteryPercentage":85,"isGPSOn":true},{"latitude":13.033381,"longitude":80.154999,"isManuallyCaptured":false,"batteryPercentage":84,"isGPSOn":true}]}}'
```

---

### 2.3 End GPS Session

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `gpsSessionEnd` |

Call when the employee finishes their trip. Returns total distance and duration.

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "gpsSessionEnd",
  "data": {
    "siteVisitGPSId": 180737,
    "userId": 1,
    "endingLatitude": 13.030574,
    "endingLongitude": 80.155511,
    "closingRemarks": "Visit completed successfully"
  }
}
```

**Response:**

```json
{
  "status": "ok",
  "data": {
    "totalWaypoints": 7,
    "totalDistanceKm": 0.79,
    "totalDuration": "00:00:01"
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"gpsSessionEnd","data":{"siteVisitGPSId":180737,"userId":1,"endingLatitude":13.030574,"endingLongitude":80.155511,"closingRemarks":"Visit completed"}}'
```

---

### 2.4 Upload GPS Photo

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `gpsPhotoUpload` |

Upload a photo taken during the trip (start location, end location, or any checkpoint).

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "gpsPhotoUpload",
  "data": {
    "siteVisitGPSId": 180737,
    "siteVisitGPSDetailId": 0,
    "imageBase64": "<base64-encoded-jpg/png>",
    "imagePath": ""
  }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| siteVisitGPSId | int | Yes | Session ID from gpsSessionStart |
| siteVisitGPSDetailId | int | No | Specific waypoint ID (0 for session-level photo) |
| imageBase64 | string | Yes | Base64-encoded image data |
| imagePath | string | No | Leave empty, server generates path |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "imageId": 1686,
    "imagePath": "gps_images/180737_0_1774251597844.jpg"
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"gpsPhotoUpload","data":{"siteVisitGPSId":180737,"imageBase64":"iVBORw0KGgoAAAANSUhEUg==","imagePath":""}}'
```

---

## 3. GPS Tracking — Read / Admin Endpoints

### 3.1 List GPS Sessions

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `siteVisitGPSList` |

Get all GPS sessions, optionally filtered by user.

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "siteVisitGPSList",
  "data": {
    "search": "",
    "limit": 50,
    "userId": 0,
    "mode": "all"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| search | string | Search by employee name |
| limit | int | Max results (default 50) |
| userId | int | Filter by specific user (0 = all) |
| mode | string | `"all"` or `"approval"` (pending approval only) |

**Response:**

```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "siteVisitGPSId": 180737,
        "refNo": "40744",
        "purpose": "Client Visit - RE Nagar Porur",
        "remarks": "Meeting with client",
        "startingDateAndTime": "2026-03-23T07:39:55Z",
        "endingDateAndTime": "2026-03-23T07:39:56Z",
        "isApproved": false,
        "approvalBy": 0,
        "reason": "",
        "userId": 1,
        "userName": "admin",
        "roleId": 1,
        "startingLocation": "13.0347580, 80.1559840",
        "endingLocation": "13.0305740, 80.1555110",
        "noOfLocation": 7,
        "noOfImages": 1,
        "totalDuration": "00:00:00",
        "createdDateAndTime": "2026-03-23T07:39:55Z"
      }
    ]
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"siteVisitGPSList","data":{"search":"","limit":50,"mode":"all"}}'
```

---

### 3.2 Get GPS Session Detail (with Waypoints)

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `siteVisitGPSDetail` |

Get full details of a single session including all waypoints.

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "siteVisitGPSDetail",
  "data": {
    "siteVisitGPSId": 180737
  }
}
```

**Response:**

```json
{
  "status": "ok",
  "data": {
    "siteVisitGPSId": 180737,
    "refNo": "40744",
    "userName": "admin",
    "purpose": "Client Visit - RE Nagar Porur",
    "startingDateAndTime": "2026-03-23T07:39:55Z",
    "endingDateAndTime": "2026-03-23T07:39:56Z",
    "totalDuration": "00:00:00",
    "waypoints": [
      { "latitude": 13.034758, "longitude": 80.155984, "isManuallyCaptured": false, "description": "Start Point" },
      { "latitude": 13.034198, "longitude": 80.155658, "isManuallyCaptured": false, "description": "" },
      { "latitude": 13.033381, "longitude": 80.154999, "isManuallyCaptured": false, "description": "" },
      { "latitude": 13.03224, "longitude": 80.15399, "isManuallyCaptured": true, "description": "Checkpoint" },
      { "latitude": 13.030964, "longitude": 80.153158, "isManuallyCaptured": false, "description": "" },
      { "latitude": 13.030578, "longitude": 80.154058, "isManuallyCaptured": false, "description": "" },
      { "latitude": 13.030574, "longitude": 80.155511, "isManuallyCaptured": false, "description": "End Point" }
    ]
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"siteVisitGPSDetail","data":{"siteVisitGPSId":180737}}'
```

---

### 3.3 Get GPS Day Map (by User + Date)

| Field | Value |
|-------|-------|
| namespace | `marketing` |
| apiName | `siteVisitGPSDayMap` |

Get all GPS waypoints for a user on a specific date. Used by the admin map view.

**Request:**

```json
{
  "namespace": "marketing",
  "apiName": "siteVisitGPSDayMap",
  "data": {
    "date": "2026-03-23",
    "userId": 1
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| date | string | Date in `YYYY-MM-DD` format |
| userId | int | Optional. If 0, returns summary of all users for that date |

**Response (with userId):**

```json
{
  "status": "ok",
  "data": {
    "date": "2026-03-23",
    "waypoints": [
      { "lat": 13.034758, "lng": 80.155984, "manual": false, "desc": "Start Point", "time": "2026-03-23T07:39:55Z", "gpsId": 180737 },
      { "lat": 13.034198, "lng": 80.155658, "manual": false, "time": "2026-03-23T07:39:56Z", "gpsId": 180737 },
      { "lat": 13.03224, "lng": 80.15399, "manual": true, "desc": "Checkpoint", "time": "2026-03-23T07:39:56Z", "gpsId": 180737 },
      { "lat": 13.030574, "lng": 80.155511, "manual": false, "desc": "End Point", "time": "2026-03-23T07:39:56Z", "gpsId": 180737 }
    ],
    "segments": [
      { "gpsId": 180737, "purpose": "Client Visit - RE Nagar Porur", "startTime": "2026-03-23T07:39:55Z", "endTime": "2026-03-23T07:39:56Z" }
    ]
  }
}
```

**Response (without userId — returns user summaries):**

```json
{
  "status": "ok",
  "data": {
    "date": "2026-03-23",
    "users": [
      { "userId": 1, "userName": "admin", "recordCount": 1, "totalPoints": 7, "totalDuration": "00:00:01", "firstStart": "...", "lastEnd": "..." }
    ]
  }
}
```

**curl:**

```bash
curl -X POST https://mms20-core-api.azurewebsites.net/api \
  -H "Content-Type: application/json" \
  -d '{"namespace":"marketing","apiName":"siteVisitGPSDayMap","data":{"date":"2026-03-23","userId":1}}'
```

---

## Quick Reference Table

| # | Endpoint | Namespace | API Name | Purpose |
|---|----------|-----------|----------|---------|
| 1 | Login | `auth` | `login` | Username + password login |
| 2 | OTP Send | `auth` | `otpSend` | Send OTP to mobile |
| 3 | OTP Verify | `auth` | `otpVerify` | Verify OTP + get user session |
| 4 | GPS Start | `marketing` | `gpsSessionStart` | Start a new trip |
| 5 | GPS Waypoints | `marketing` | `gpsWaypointPost` | Post GPS coordinates (batch) |
| 6 | GPS End | `marketing` | `gpsSessionEnd` | End trip, get distance/duration |
| 7 | GPS Photo | `marketing` | `gpsPhotoUpload` | Upload trip photo (base64) |
| 8 | GPS List | `marketing` | `siteVisitGPSList` | List all sessions |
| 9 | GPS Detail | `marketing` | `siteVisitGPSDetail` | Get session with waypoints |
| 10 | GPS Day Map | `marketing` | `siteVisitGPSDayMap` | Get user's day route for map |

---

## Mobile App Integration Flow

```
┌─────────────────────────────────────────────────────────┐
│                    MOBILE APP FLOW                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  1. LOGIN                                               │
│     ├── Option A: auth/login (username + password)      │
│     └── Option B: auth/otpSend → auth/otpVerify (OTP)  │
│         Store: userId, userName, roleId, isAdmin        │
│                                                         │
│  2. START TRIP                                          │
│     └── marketing/gpsSessionStart                       │
│         Input: userId, purpose, lat/lng                 │
│         Store: siteVisitGPSId                           │
│                                                         │
│  3. DURING TRIP (every 30 seconds)                      │
│     └── marketing/gpsWaypointPost                       │
│         Input: siteVisitGPSId, waypoints[]              │
│         Batch up to 10 waypoints per call               │
│                                                         │
│  4. TAKE PHOTOS (optional, at any point)                │
│     └── marketing/gpsPhotoUpload                        │
│         Input: siteVisitGPSId, imageBase64              │
│                                                         │
│  5. END TRIP                                            │
│     └── marketing/gpsSessionEnd                         │
│         Input: siteVisitGPSId, ending lat/lng           │
│         Returns: totalDistance, totalDuration            │
│                                                         │
│  6. VIEW HISTORY (optional)                             │
│     ├── marketing/siteVisitGPSList (my sessions)        │
│     └── marketing/siteVisitGPSDetail (session detail)   │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

**All endpoints tested on production:** `https://mms20-core-api.azurewebsites.net/api`
**Last tested:** 2026-03-23
**Status:** All 10 endpoints returning `status: "ok"` ✅
