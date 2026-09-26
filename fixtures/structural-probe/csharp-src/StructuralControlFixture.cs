using System;
using System.Collections.Generic;

namespace StructuralProbe;

public interface IGateway
{
    string Load(string value);
}

public sealed class StructuralControlFixture
{
    private static bool A(string? value) => value is not null;
    private static bool B(string value) => value.Length > 1;
    private static bool C(string value) => value.StartsWith("x", StringComparison.Ordinal);
    private static string Nested(string? value) => value is null ? "" : value.Trim();

    public string ExerciseStructuralProbe(List<string> items, int mode, IGateway gateway)
    {
        string value = Nested(items[0]);

        if (A(value) && (B(value) || C(value)))
        {
            value = Nested(value);
        }
        else
        {
            value = Nested("else");
        }

        switch (mode)
        {
            case 1:
                value = Nested("one");
                break;
            case 2:
                return gateway.Load(value);
            default:
                value = Nested("default");
                break;
        }

        string selected = mode > 0 ? gateway.Load(value) : Nested(value);

        value = Nested(value) + Nested(value);

        for (int i = 0; i < items.Count; i++)
        {
            if (i == 1)
            {
                continue;
            }

            if (i > 3)
            {
                break;
            }

            value = Nested(items[i]);
        }

        foreach (string item in items)
        {
            value = Nested(item);
        }

        while (A(value))
        {
            value = Nested(value);
            break;
        }

        try
        {
            if (selected is null)
            {
                throw new InvalidOperationException("selected");
            }

            value = gateway.Load(selected);
        }
        catch (InvalidOperationException error)
        {
            value = Nested(error.Message);
        }
        finally
        {
            Nested("finally");
        }

        if (value.Length == 0)
        {
            return "empty";
        }

        return value;
    }
}
