import Foundation

@main
struct PermissionShiftTimingTests {
    static func main() {
        let shift = PermissionShiftTiming(startTime: "10:00", endTime: "19:00")
        precondition(shift.error(from: "10:00", to: "11:00") == nil)
        precondition(shift.error(from: "18:00", to: "19:00") == nil)
        precondition(shift.error(from: "12:00", to: "13:00") != nil)
        precondition(shift.error(from: "10:00", to: "23:29") != nil)
        precondition(shift.error(from: "09:00", to: "19:00") != nil)
        precondition(shift.error(from: "19:00", to: "10:00") != nil)
        precondition(shift.error(from: "25:00", to: "19:00") != nil)
        precondition(PermissionShiftTiming(startTime: "10:00", endTime: "19:00", isWorkDay: false).error(from: nil, to: nil) != nil)
        precondition(shift.defaultEndTime == "11:00")
        precondition(PermissionShiftTiming(startTime: "10:00", endTime: "10:30").defaultEndTime == "10:30")
        precondition(PermissionShiftTiming(startTime: "22:00", endTime: "06:00").error(from: nil, to: nil) != nil)
        precondition(shift.error(from: nil, to: nil) == nil)
        print("PermissionShiftTiming: 12 assertions passed")
    }
}
