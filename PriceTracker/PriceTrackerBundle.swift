import WidgetKit
import SwiftUI

@main
struct PriceTrackerBundle: WidgetBundle {
    var body: some Widget {
        CryptoLiveActivity()
        PortfolioLiveActivity()
    }
}
