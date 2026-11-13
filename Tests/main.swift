import Foundation

runCompxCodecTests()
runStatusModelTests()
runSettingsTests()

if failed {
    fputs("tests failed\n", stderr)
    exit(1)
}
print("tests passed")
