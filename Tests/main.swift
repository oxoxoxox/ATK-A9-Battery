import Foundation

runCompxCodecTests()

if failed {
    fputs("CompxCodec tests failed\n", stderr)
    exit(1)
}
print("CompxCodec tests passed")
