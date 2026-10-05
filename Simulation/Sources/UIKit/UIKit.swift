open class UIImage {
    public let systemName: String
    public init?(systemName: String) { self.systemName = systemName }
}
open class UIColor {
    public init() {}
    public static let label = UIColor(), secondaryLabel = UIColor(), white = UIColor(), systemBlue = UIColor()
}
public enum UIBlurEffect { public enum Style { case systemThickMaterial, systemMaterial } }
