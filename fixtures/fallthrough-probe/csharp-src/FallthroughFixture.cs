namespace FallthroughProbe;

public sealed class FallthroughFixture
{
    private static void CallA()
    {
    }

    private static void CallB()
    {
    }

    private static void CallDefault()
    {
    }

    public void ExerciseFallthrough(int mode)
    {
        switch (mode)
        {
            case 1:
                CallA();
                goto case 2;
            case 2:
                CallB();
                break;
            default:
                CallDefault();
                break;
        }
    }
}
