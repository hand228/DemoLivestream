import Foundation

struct Preference {
    static var defaultInstance: Preference = Preference()

    var uri: String? = "rtmp://a.rtmp.youtube.com/live2"
    var streamName: String? = "17a8-9crz-3p00-19a5"
}
