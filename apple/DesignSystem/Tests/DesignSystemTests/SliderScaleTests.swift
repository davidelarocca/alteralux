import Testing
@testable import DesignSystem

/// How a slider lays its values along its track.
struct SliderScaleTests {
    @Test func aLinearScaleIsTheValue() {
        #expect(SliderScale.linear.position(5250) == 5250)
        #expect(SliderScale.linear.value(of: 5250) == 5250)
    }

    /// On the reciprocal scale equal steps of the track are equal steps in mired: 2000 to 2500 K
    /// takes as much room as 5000 to 10000 K (100 mired each), and larger values stay to the right.
    @Test func aReciprocalScaleIsEvenInMired() {
        let scale = SliderScale.reciprocal
        let warm = scale.position(2500) - scale.position(2000)
        let cool = scale.position(10000) - scale.position(5000)
        #expect(abs(warm - cool) < 1e-12)
        #expect(scale.position(12000) > scale.position(2000))
        for kelvin in [2000.0, 4321, 6500, 12000] {
            #expect(abs(scale.value(of: scale.position(kelvin)) - kelvin) < 1e-6)
        }
    }
}
