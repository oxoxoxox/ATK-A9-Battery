import Foundation

runCompxCodecTests()
runStatusModelTests()
runMenuBarButtonTests()
runMenuBarIconTests()

if failed {
    fputs("tests failed\n", stderr)
    exit(1)
}
print("tests passed")
