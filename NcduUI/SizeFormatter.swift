import Foundation

/// Human-readable size formatting, mirroring ncdu's `formatsize` / `fullsize`
/// (see reference/ncdu/src/util.c). Defaults to base-1024 (IEC) units like ncdu.
enum SizeFormatter {
    /// Returns a short string like "12.3 MiB", matching ncdu's "%5.1f <unit>".
    static func short(_ bytes: Int64, si: Bool = false) -> String {
        var r = Double(bytes)
        let unit: String

        if si {
            if r < 1000 { unit = "B" }
            else if r < 1e6 { unit = "kB"; r /= 1e3 }
            else if r < 1e9 { unit = "MB"; r /= 1e6 }
            else if r < 1e12 { unit = "GB"; r /= 1e9 }
            else if r < 1e15 { unit = "TB"; r /= 1e12 }
            else if r < 1e18 { unit = "PB"; r /= 1e15 }
            else { unit = "EB"; r /= 1e18 }
        } else {
            if r < 1000 { unit = "B" }
            else if r < 1023e3 { unit = "KiB"; r /= 1024 }
            else if r < 1023e6 { unit = "MiB"; r /= 1_048_576 }
            else if r < 1023e9 { unit = "GiB"; r /= 1_073_741_824 }
            else if r < 1023e12 { unit = "TiB"; r /= 1_099_511_627_776 }
            else if r < 1023e15 { unit = "PiB"; r /= 1_125_899_906_842_624 }
            else { unit = "EiB"; r /= 1_152_921_504_606_846_976 }
        }

        if unit == "B" {
            return "\(Int64(r)) \(unit)"
        }
        return String(format: "%.1f %@", r, unit)
    }

    /// Full byte count with thousands separators, like ncdu's `fullsize`.
    static func full(_ bytes: Int64) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        return (nf.string(from: NSNumber(value: bytes)) ?? "\(bytes)") + " B"
    }
}
