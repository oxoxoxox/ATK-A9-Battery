import Foundation

runCompxCodecTests()
runStatusModelTests()
runSettingsTests()
runMenuBarButtonTests()

if failed {
    fputs("tests failed\n", stderr)
    exit(1)
}
print("tests passed")
