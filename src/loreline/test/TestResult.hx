package loreline.test;

/**
 * Result of running a test case.
 */
class TestResult {

    /** The related test case */
    public final testCase:TestCase;

    /** Whether the test passed */
    public final passed:Bool;

    /** The actual output produced */
    public final actualOutput:String;

    /** Error message if test failed */
    public final error:Error;

    public function new(testCase:TestCase, passed:Bool, actualOutput:String, ?error:Error) {
        this.testCase = testCase;
        this.passed = passed;
        this.actualOutput = actualOutput;
        this.error = error;
    }

}
