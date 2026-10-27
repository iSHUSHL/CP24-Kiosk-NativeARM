import Foundation

enum Channel: String, CaseIterable {
    case cp24
    case citynews
    case globalToronto

    var title: String {
        switch self {
        case .cp24:
            return "CP24"
        case .citynews:
            return "CityNews"
        case .globalToronto:
            return "Global News Toronto"
        }
    }

    var playback: Playback {
        switch self {
        case .cp24:
            return .native(URL(string: "https://live-news.video.9c9media.com/f/news/cp24/manifest.m3u8")!)
        case .citynews:
            return .native(URL(string: "https://citynewsregional.akamaized.net/hls/live/20002916/Regional_Live_6/master.m3u8")!)
        case .globalToronto:
            return .native(URL(string: "https://content.news.corusappservices.com/templates/media/smil/deb8cec5-87fb-460a-ab82-0929374fc5fb?delivery_protocol=hls&metafile=false")!)
        }
    }

    var next: Channel {
        switch self {
        case .cp24:
            return .citynews
        case .citynews:
            return .globalToronto
        case .globalToronto:
            return .cp24
        }
    }

    enum Playback {
        case native(URL)
    }
}
