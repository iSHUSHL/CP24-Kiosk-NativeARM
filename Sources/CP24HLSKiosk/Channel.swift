import Foundation

enum Channel: String, CaseIterable {
    case cp24
    case citynews

    var title: String {
        switch self {
        case .cp24:
            return "CP24"
        case .citynews:
            return "CityNews"
        }
    }

    var playback: Playback {
        switch self {
        case .cp24:
            return .native(URL(string: "https://live-news.video.9c9media.com/f/news/cp24/manifest.m3u8")!)
        case .citynews:
            return .native(URL(string: "https://citynewsregional.akamaized.net/hls/live/1017963/Regional_Live_6/master.m3u8")!)
        }
    }

    var next: Channel {
        switch self {
        case .cp24:
            return .citynews
        case .citynews:
            return .cp24
        }
    }

    enum Playback {
        case native(URL)
    }
}
