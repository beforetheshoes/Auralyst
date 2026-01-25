import Foundation

extension Decimal {
    var nsDecimalNumber: NSDecimalNumber {
        NSDecimalNumber(decimal: self)
    }
}

extension NSDecimalNumber {
    var decimal: Decimal { decimalValue }
}
