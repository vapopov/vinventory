import Foundation

// Protocol adaptation from iscarelli/niimbot-web-bluetooth (MIT).
// See THIRD_PARTY_NOTICES.md. This implementation targets B1 model ID 4096.
struct NiimbotFrame: Equatable {
    var command: UInt8
    var payload: [UInt8]
    func encoded() throws -> Data {
        guard payload.count <= 255 else { throw InventoryError.message("Niimbot packet payload is too large.") }
        let length = UInt8(payload.count)
        let checksum = payload.reduce(command ^ length, ^)
        return Data([0x55, 0x55, command, length] + payload + [checksum, 0xaa, 0xaa])
    }
}

struct NiimbotFrameDecoder {
    private var buffer: [UInt8] = []
    mutating func append(_ data: Data) -> [NiimbotFrame] {
        buffer.append(contentsOf: data)
        var frames: [NiimbotFrame] = []
        while buffer.count >= 2 {
            guard buffer[0] == 0x55, buffer[1] == 0x55 else { buffer.removeFirst(); continue }
            guard buffer.count >= 4 else { break }
            let length = Int(buffer[3]), total = length + 7
            if buffer.count < total {
                // Recover from a stray header byte ahead of a complete valid frame.
                let next = (1..<max(1, buffer.count - 6)).first { index in
                    guard buffer[index] == 0x55, buffer[index + 1] == 0x55 else { return false }
                    let end = index + Int(buffer[index + 3]) + 7
                    guard end <= buffer.count else { return false }
                    let checksum = buffer[(index + 4)..<(end - 3)].reduce(buffer[index + 2] ^ buffer[index + 3], ^)
                    return buffer[end - 3] == checksum && buffer[end - 2] == 0xaa && buffer[end - 1] == 0xaa
                }
                if let next { buffer.removeFirst(next); continue }
                break
            }
            let payload = Array(buffer[4..<(4 + length)])
            let checksum = payload.reduce(buffer[2] ^ buffer[3], ^)
            guard buffer[4 + length] == checksum, buffer[5 + length] == 0xaa, buffer[6 + length] == 0xaa else { buffer.removeFirst(); continue }
            frames.append(NiimbotFrame(command: buffer[2], payload: payload))
            buffer.removeFirst(total)
        }
        return frames
    }
}

struct NiimbotRaster {
    static let b1Width = 384
    static let b1Height = 240
    var width: Int
    var height: Int
    var bytes: [UInt8]
    var stride: Int { (width + 7) / 8 }
    func rowFrames() throws -> [NiimbotFrame] {
        guard width > 0, width <= 384, height > 0, height <= 65535,
              bytes.count == stride * height else { throw InventoryError.message("Invalid B1 label raster.") }
        var frames: [NiimbotFrame] = []
        var row = 0
        while row < height {
            let pixels = Array(bytes[(row * stride)..<((row + 1) * stride)])
            var run = 1
            while row + run < height && run < 200 && Array(bytes[((row + run) * stride)..<((row + run + 1) * stride)]) == pixels { run += 1 }
            let position: [UInt8] = [UInt8(row >> 8), UInt8(row & 255)]
            if pixels.allSatisfy({ $0 == 0 }) {
                frames.append(NiimbotFrame(command: 0x84, payload: position + [UInt8(run)]))
            } else {
                let count = pixels.reduce(0) { $0 + $1.nonzeroBitCount }
                frames.append(NiimbotFrame(command: 0x85, payload: position + [0, UInt8(count & 255), UInt8(count >> 8), UInt8(run)] + pixels))
            }
            row += run
        }
        return frames
    }
    static func pageSize(copies: Int) throws -> [UInt8] {
        guard (1...20).contains(copies) else { throw InventoryError.message("Choose 1–20 copies.") }
        return [UInt8(b1Height >> 8), UInt8(b1Height & 255), UInt8(b1Width >> 8), UInt8(b1Width & 255), 0, UInt8(copies)]
    }
}
