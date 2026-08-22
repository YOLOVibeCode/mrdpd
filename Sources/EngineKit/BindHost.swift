/// T1-SEC-04 bind-address policy for the Swift lab process. Not an ABI symbol.
public enum BindHost {
    public static func isSpecified(_ host: String) -> Bool {
        switch host {
        case "", "0.0.0.0", "::", "*":
            return false
        default:
            return true
        }
    }
}
