extension String {
    /// Decode a null-terminated C-string buffer (the form every libproc and
    /// sysctl call hands back) without the deprecated `init(cString:)`.
    init(nullTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}
