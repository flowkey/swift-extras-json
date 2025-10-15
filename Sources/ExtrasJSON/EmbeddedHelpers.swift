#if hasFeature(Embedded)
@inlinable
public func memmove(dest: UnsafeMutableRawPointer,
                         src: UnsafeRawPointer,
                         size: Int) {
  if size <= 0 || dest == src { return }

  let d = dest.bindMemory(to: UInt8.self, capacity: size)
  let s = src.bindMemory(to: UInt8.self, capacity: size)

  // Compare raw addresses to detect overlap direction
  let dAddr = UInt(bitPattern: d)
  let sAddr = UInt(bitPattern: s)

  if sAddr < dAddr && dAddr < sAddr &+ UInt(size) {
    // Overlap and dest starts inside src: copy backwards
    var i = size
    while i > 0 {
      i &-= 1
      d[i] = s[i]
    }
  } else {
    // No harmful overlap: copy forwards
    var i = 0
    while i < size {
      d[i] = s[i]
      i &+= 1
    }
  }
}
#endif
