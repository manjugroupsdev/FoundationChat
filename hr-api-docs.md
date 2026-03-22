# API Endpoints Reference

All endpoints use `POST /api` with JSON body: `{ "namespace": "<ns>", "apiName": "<name>", "data": {...} }`

Base URL: `http://localhost:8080/api`

---

## Permissions Module

### List Permissions

Fetch all permission requests with optional filters.

**Namespace:** `hr` | **API Name:** `mobilePermissionsList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "mobilePermissionsList",
    "data": {
      "limit": 50,
      "mode": "all",
      "userId": 0,
      "search": ""
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "mobilePermissionId": 26508,
        "employeeId": 66,
        "employeeName": "Test User",
        "employeeCode": "1",
        "departmentName": "Telesales",
        "permissionDate": "2026-03-19T00:00:00Z",
        "reason": "Personal",
        "expectedDurationInMins": 60,
        "beginningDateTime": "2026-03-19T15:00:00Z",
        "endingDateTime": "2026-03-19T16:00:00Z",
        "totalDurationInMins": 60,
        "closingRemarks": "",
        "approvalStatus": "Rejected",
        "approvalByText": "admin",
        "approvalDateTime": "2026-03-19T07:26:31Z"
      }
    ]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `limit` | number | Max records to return (default: 200) |
| `mode` | string | `"all"` or `"approval"` (pending only) |
| `userId` | number | Filter by user ID (0 = all) |
| `search` | string | Search by employee name/code |

---

### Save Permission Request

Create or update a permission request.

**Namespace:** `hr` | **API Name:** `mobilePermissionSave`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "mobilePermissionSave",
    "data": {
      "mobilePermissionId": 0,
      "employeeId": 1040,
      "permissionDate": "2026-03-21",
      "reason": "Doctor visit",
      "expectedDurationInMins": 60,
      "userId": 1
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "mobilePermissionId": 26509,
    "saved": true
  }
}
```

---

### Approve/Reject Permission

**Namespace:** `hr` | **API Name:** `mobilePermissionApprovalSave`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "mobilePermissionApprovalSave",
    "data": {
      "mobilePermissionId": 26508,
      "approvalStatus": "Approved",
      "approvalRemarks": "OK",
      "userId": 1
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "mobilePermissionId": 26508,
    "saved": true
  }
}
```

| `approvalStatus` values | Description |
|--------------------------|-------------|
| `"Approved"` | Approve the permission |
| `"Rejected"` | Reject the permission |

---

## Attendance Module

### List Mobile Attendance

Fetch mobile punch-in/out records.

**Namespace:** `hr` | **API Name:** `mobileAttendanceList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "mobileAttendanceList",
    "data": {
      "limit": 50,
      "mode": "all",
      "userId": 0,
      "fromDate": "",
      "toDate": "",
      "search": ""
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "mobileAttendanceId": 414438,
        "employeeId": 1299,
        "employeeName": "SABARINATH.R - 21819, Manager (SALES)",
        "empUserName": "SABARINATH.R",
        "empUserId": 1659,
        "departmentName": "Sales & Marketing",
        "inDateAndTime": "2026-03-19T19:25:30Z",
        "outDateAndTime": null,
        "totalDurationInMins": 0,
        "lateEntryDurationInMins": 0,
        "earlyExitDurationInMins": 0,
        "approvedAttendance": "",
        "approvalRemarks": "",
        "attendanceApprovalByUserName": "VINODH.R",
        "needApproval": true,
        "startingLocation": "",
        "endingLocation": "",
        "empUserMobileNo": "9731314110",
        "punchTimings": "",
        "startingLatitude": 0,
        "startingLongitude": 0,
        "endingLatitude": 0,
        "endingLongitude": 0,
        "approvedAttendanceValue": 0
      }
    ]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `mode` | string | `"all"` = all records, `"approval"` = pending approval only |
| `fromDate` | string | Filter start date (ISO format) |
| `toDate` | string | Filter end date (ISO format) |

---

### Approve Mobile Attendance

**Namespace:** `hr` | **API Name:** `mobileAttendanceApprovalSave`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "mobileAttendanceApprovalSave",
    "data": {
      "mobileAttendanceId": 414438,
      "approvedAttendance": "Present",
      "approvalRemarks": "Verified",
      "userId": 1
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "mobileAttendanceId": 414438,
    "saved": true
  }
}
```

| `approvedAttendance` values | Description |
|-----------------------------|-------------|
| `"Present"` | Full day present (value = 1.0) |
| `"HalfDay"` | Half day (value = 0.5) |
| `"Approved"` | Generic approval |
| `"Rejected"` | Reject attendance |

---

### List Daily Attendance

**Namespace:** `hr` | **API Name:** `dailyAttendanceList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "dailyAttendanceList",
    "data": {
      "date": "2025-12-02",
      "departmentId": 0,
      "employeeId": 0,
      "search": "",
      "limit": 50
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "dailyAttendanceId": 292988,
        "employeeId": 1040,
        "employeeName": "PARAMESHWARI.R",
        "employeeCode": "26012",
        "departmentName": "Telesales",
        "designationName": "Lead Management Executive",
        "shiftDescription": "",
        "dateAndTime": "2025-12-02",
        "morningSession": "P",
        "eveningSession": "P",
        "inTime": "10:29:00",
        "outTime": "18:26:00",
        "totalHours": "07:57:00",
        "otInMins": 0,
        "workingDurationInMins": 477,
        "attendanceValue": 1,
        "morningRemarks": "Late Entry",
        "eveningRemarks": "",
        "isVerified": true,
        "createdUserName": "",
        "createdDate": "2025-12-06"
      }
    ]
  }
}
```

---

### Monthly Attendance Grid

Returns employee-wise day grid with attendance values for each day of the month.

**Namespace:** `hr` | **API Name:** `monthlyAttendanceList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "monthlyAttendanceList",
    "data": {
      "month": 12,
      "year": 2025,
      "departmentId": 0,
      "search": "",
      "limit": 100
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "employeeId": 1337,
        "employeeName": "ABINAYA.S",
        "employeeCode": "21857",
        "departmentName": "Telesales",
        "designationName": "Lead Management Executive",
        "totalPresent": 22,
        "totalAbsent": 3,
        "totalLeave": 1,
        "totalHolidays": 0,
        "totalWeekOffs": 0,
        "totalWorkingDays": 26,
        "totalOtMins": 0,
        "lateEntries": 0,
        "earlyExits": 0,
        "dayWise": [
          { "day": 1, "attendanceValue": 1, "attendanceType": "Present", "inTime": "09:15:00", "outTime": "18:30:00", "remarks": "" },
          { "day": 2, "attendanceValue": 0, "attendanceType": "Absent", "inTime": "", "outTime": "", "remarks": "" }
        ]
      }
    ]
  }
}
```

---

### Attendance for Period

Aggregated attendance summary per employee for a date range.

**Namespace:** `hr` | **API Name:** `attendanceForPeriodList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "attendanceForPeriodList",
    "data": {
      "fromDate": "2025-12-01",
      "toDate": "2025-12-31",
      "departmentId": 0,
      "search": "",
      "limit": 100
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "employeeId": 1337,
        "employeeName": "ABINAYA.S",
        "employeeCode": "21857",
        "departmentName": "Telesales",
        "designationName": "Lead Management Executive",
        "totalPresent": 1,
        "totalAbsent": 0,
        "totalLeave": 0,
        "totalHoliday": 0,
        "totalWeekOff": 0,
        "totalDays": 2,
        "totalOtMins": 0
      }
    ]
  }
}
```

---

### Attendance Summary (Department-wise)

**Namespace:** `hr` | **API Name:** `attendanceSummaryList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "attendanceSummaryList",
    "data": {
      "month": 12,
      "year": 2025,
      "limit": 50
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "departmentName": "Accounts",
        "totalEmployees": 7,
        "totalPresent": 4.5,
        "totalAbsent": 0,
        "totalLeave": 0,
        "totalLateEntry": 0,
        "totalEarlyExit": 0,
        "avgWorkingHours": 8.01
      }
    ]
  }
}
```

---

### Attendance Not Posted

Employees who haven't submitted attendance for a given date.

**Namespace:** `hr` | **API Name:** `attendanceNotPostedList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "attendanceNotPostedList",
    "data": {
      "date": "2025-12-15",
      "departmentId": 0,
      "search": "",
      "limit": 100
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "employeeId": 1337,
        "employeeName": "ABINAYA.S",
        "employeeCode": "21857",
        "departmentName": "Telesales",
        "designationName": "Lead Management Executive",
        "mobileNo": "9626228944",
        "lastAttendance": "2025-12-13 08:00:50"
      }
    ]
  }
}
```

---

### Absent List

Employees marked absent on a date or date range.

**Namespace:** `hr` | **API Name:** `absentList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "hr",
    "apiName": "absentList",
    "data": {
      "date": "2025-12-02",
      "departmentId": 0,
      "search": "",
      "limit": 100
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "employeeId": 825,
        "employeeName": "ABIRAMI.G",
        "employeeCode": "21359",
        "departmentName": "Accounts",
        "designationName": "Accounts Executive",
        "absentDate": "2025-12-02",
        "absentType": "Absent"
      }
    ]
  }
}
```

---

## Call Followup Module

### List Call Logs

Fetch call log entries with lead details and followup info.

**Namespace:** `marketing` | **API Name:** `callLogsList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "callLogsList",
    "data": {
      "limit": 50,
      "search": ""
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "callLogId": 8631016,
        "callStatusId": 4,
        "clientId": 219314,
        "callRefNo": "A8179340",
        "createdDateAndTime": "2025-12-13T17:41:40Z",
        "clientName": "Mr.Rajkumar",
        "mobileNumber": "9094465476",
        "location": "++nil",
        "pincode": "00",
        "nameOfProject": "GS TMZ 4.O",
        "callSource": "CP - Srinivas",
        "callStatus": "Hot",
        "callType": "Followup",
        "assignedTo": "",
        "hodFullName": "",
        "reason": "",
        "remarks": "call back next week saturday sv confirm",
        "reviewDateTime": "2025-12-16T10:30:00Z",
        "clientVisited": false
      }
    ]
  }
}
```

---

### Save Lead Followup

Log a followup action on a call/lead.

**Namespace:** `marketing` | **API Name:** `leadFollowupSave`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "leadFollowupSave",
    "data": {
      "callLogId": 8631016,
      "nextReviewDate": "2026-04-01",
      "remarks": "Client interested, callback next week",
      "callStatusId": 4,
      "userId": 1
    }
  }'
```

---

### Call Source Summary

Aggregated lead funnel metrics grouped by source.

**Namespace:** `marketing` | **API Name:** `callSourceSummaryList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "callSourceSummaryList",
    "data": {
      "limit": 50
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "callSource": "Database",
        "totalLeads": 2628364,
        "totalCPFixed": 2017,
        "totalCPDone": 0,
        "cpToSV": 0,
        "leadToSV": 11435,
        "totalSVFixed": 11432,
        "totalSVDone": 11435,
        "booked": 169,
        "hold": 0,
        "notInterested": 17956
      },
      {
        "callSource": "facebook",
        "totalLeads": 1131094,
        "totalCPFixed": 1424,
        "totalSVDone": 7540,
        "booked": 91,
        "notInterested": 12443
      }
    ]
  }
}
```

---

### Team Call Source Summary

Same as callSourceSummary but grouped by team.

**Namespace:** `marketing` | **API Name:** `teamCallSourceSummaryList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "teamCallSourceSummaryList",
    "data": {
      "limit": 50
    }
  }'
```

---

## Site Visits Module

### List Site Visits

Fetch scheduled and completed site visits.

**Namespace:** `marketing` | **API Name:** `siteVisitsList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitsList",
    "data": {
      "limit": 50,
      "search": ""
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "siteVisitId": 235466,
        "siteVisitRefNo": "74610",
        "siteVisitDate": "2025-12-13T00:00:00Z",
        "clientName": "Mr.Syed",
        "mobileNumber": "9535842774",
        "projectName": "Luxury X - Grandeur Bungalows",
        "currentStatusId": 62,
        "currentStatusText": "Site Reached",
        "siteIncharge": "CHITRA.P",
        "confirmedByName": "CHITRA.P",
        "pickupLocation": "",
        "pickupTime": "04:00 pm",
        "bookingStatusId": 0,
        "bookingStatusText": "",
        "bookingId": 0
      }
    ]
  }
}
```

---

### Site Visit Summary

Aggregated counts by visit status.

**Namespace:** `marketing` | **API Name:** `siteVisitSummaryList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitSummaryList",
    "data": {
      "limit": 50
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      { "label": "Counselling Completed", "siteVisitCnt": 21542, "bookingCnt": 21525 },
      { "label": "SV Fixed", "siteVisitCnt": 10332, "bookingCnt": 10327 }
    ]
  }
}
```

---

### Site Visit GPS List

GPS tracking records for field staff visits.

**Namespace:** `marketing` | **API Name:** `siteVisitGPSList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitGPSList",
    "data": {
      "limit": 50
    }
  }'
```

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

---

### Update Site Visit Status

**Namespace:** `marketing` | **API Name:** `siteVisitStatusSave`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "siteVisitStatusSave",
    "data": {
      "siteVisitId": 235466,
      "statusId": 62,
      "statusText": "Site Reached",
      "userId": 1
    }
  }'
```

---

### Visitor Register

Office visitor log.

**Namespace:** `marketing` | **API Name:** `visitorRegisterList`

```bash
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "visitorRegisterList",
    "data": {
      "limit": 50
    }
  }'
```

**Response:**
```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "visitorId": 977,
        "visitorName": "Mr.Vinoth kumar.M",
        "mobileNo": "8300214364",
        "location": "Chennai",
        "visitDate": "2025-12-12T00:00:00Z",
        "inDateTime": "2025-12-12T14:00:00Z",
        "outDateTime": "2025-12-12T15:30:00Z",
        "visitPurpose": "Interview",
        "visitorCategory": "Interview Candidate",
        "visitedStaffName": "PRIYADHARSHINI.M - 21688",
        "companyName": ""
      }
    ]
  }
}
```

---

### Assign CP Visit

**Namespace:** `marketing` | **API Name:** `assignCPVisitList` / `assignCPVisitSave`

```bash
# List
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "assignCPVisitList",
    "data": { "limit": 50 }
  }'

# Save
curl -s -X POST http://localhost:8080/api \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "marketing",
    "apiName": "assignCPVisitSave",
    "data": {
      "siteVisitId": 235466,
      "assignedUserId": 1303,
      "userId": 1
    }
  }'
```

---

## Quick Reference

### All Endpoints at a Glance

| Module | Namespace | API Name | Method |
|--------|-----------|----------|--------|
| **Permissions** | `hr` | `mobilePermissionsList` | List |
| | `hr` | `mobilePermissionSave` | Create/Update |
| | `hr` | `mobilePermissionApprovalSave` | Approve/Reject |
| **Attendance** | `hr` | `mobileAttendanceList` | List mobile punches |
| | `hr` | `mobileAttendanceApprovalSave` | Approve attendance |
| | `hr` | `dailyAttendanceList` | List daily records |
| | `hr` | `dailyAttendanceSave` | Save daily record |
| | `hr` | `dailyAttendanceDelete` | Delete daily record |
| | `hr` | `monthlyAttendanceList` | Monthly grid |
| | `hr` | `attendanceForPeriodList` | Period summary |
| | `hr` | `attendanceSummaryList` | Dept summary |
| | `hr` | `attendanceNotPostedList` | Missing attendance |
| | `hr` | `absentList` | Absent employees |
| **Call Followup** | `marketing` | `callLogsList` | List call logs |
| | `marketing` | `leadFollowupSave` | Save followup |
| | `marketing` | `callSourceSummaryList` | Source metrics |
| | `marketing` | `teamCallSourceSummaryList` | Team metrics |
| **Site Visits** | `marketing` | `siteVisitsList` | List visits |
| | `marketing` | `siteVisitSummaryList` | Visit summary |
| | `marketing` | `siteVisitGPSList` | GPS tracking |
| | `marketing` | `siteVisitStatusSave` | Update status |
| | `marketing` | `visitorRegisterList` | Visitor log |
| | `marketing` | `assignCPVisitList` | CP assignments |
| | `marketing` | `assignCPVisitSave` | Assign CP |
| | `marketing` | `visitPurposesList` | Visit purposes |
| | `marketing` | `visitorCategoriesList` | Visitor categories |
