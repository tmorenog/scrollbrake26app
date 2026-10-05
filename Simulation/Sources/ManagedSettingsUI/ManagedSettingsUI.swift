// Fake ManagedSettingsUI that keeps the text so tests can read the shield.
import ManagedSettings
import UIKit

public struct ShieldConfiguration {
    public struct Label {
        public let text: String
        public init(text: String, color: UIColor) { self.text = text }
    }

    public let title: Label?
    public let subtitle: Label?
    public let primaryButtonLabel: Label?
    public let secondaryButtonLabel: Label?

    public init(backgroundBlurStyle: UIBlurEffect.Style? = nil, backgroundColor: UIColor? = nil, icon: UIImage? = nil,
                title: Label? = nil, subtitle: Label? = nil, primaryButtonLabel: Label? = nil,
                primaryButtonBackgroundColor: UIColor? = nil, secondaryButtonLabel: Label? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.primaryButtonLabel = primaryButtonLabel
        self.secondaryButtonLabel = secondaryButtonLabel
    }
}

open class ShieldConfigurationDataSource {
    public init() {}
    open func configuration(shielding application: Application) -> ShieldConfiguration { ShieldConfiguration() }
    open func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { ShieldConfiguration() }
    open func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { ShieldConfiguration() }
    open func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { ShieldConfiguration() }
}
