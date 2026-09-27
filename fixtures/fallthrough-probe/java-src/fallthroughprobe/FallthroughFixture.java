package fallthroughprobe;

public final class FallthroughFixture {
    static void callA() {
    }

    static void callB() {
    }

    static void callDefault() {
    }

    public void exerciseFallthrough(int mode) {
        switch (mode) {
            case 1:
                callA();
            case 2:
                callB();
                break;
            default:
                callDefault();
        }
    }
}
