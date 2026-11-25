import Foundation

@main
struct PunchPlaceLabelTests {
    static func main() {
        typealias L = PunchPlaceLabel
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }

        check(L.shortName(subLocality: "Ekkattuthangal", locality: "Chennai", subAdminArea: "Chennai District")
              == "Ekkattuthangal, Chennai", "area + city")
        check(L.shortName(subLocality: nil, locality: "Chennai", subAdminArea: "Chennai") == "Chennai", "city alone")
        check(L.shortName(subLocality: "Sriperumbudur", locality: nil, subAdminArea: "Kancheepuram")
              == "Sriperumbudur, Kancheepuram", "district stands in for city")
        check(L.shortName(subLocality: "coimbatore", locality: "Coimbatore", subAdminArea: nil) == "Coimbatore",
              "no repeat")
        check(L.shortName(subLocality: "600032", locality: "Chennai", subAdminArea: nil) == "Chennai", "postcode dropped")
        check(L.shortName(subLocality: "2WX4+2M", locality: "  Chennai ", subAdminArea: nil) == "Chennai",
              "plus code dropped, trimmed")
        check(L.shortName(subLocality: " ", locality: nil, subAdminArea: "") == nil, "blanks")
        check(L.shortName(subLocality: nil, locality: nil, subAdminArea: nil) == nil, "nothing")
        check(L.shortName(subLocality: String(repeating: "A", count: 50), locality: "Chennai", subAdminArea: nil)
              == String(repeating: "A", count: 31) + "…, Chennai", "long part shortened")

        check(L.overlayText(placeName: nil, latitude: 13.044340, longitude: 80.198482) == "13.04434, 80.19848",
              "compact coordinates fallback")
        check(L.overlayText(placeName: " ", latitude: 13.044340, longitude: 80.198482) == "13.04434, 80.19848",
              "blank name falls back")
        check(L.overlayText(placeName: nil, latitude: nil, longitude: 80) == "Location unavailable", "no location")
        check(L.overlayText(placeName: "Guindy, Chennai", latitude: 13, longitude: 80.2) == "Guindy, Chennai", "name")

        print("PunchPlaceLabelTests: \(count) checks passed")
    }
}
