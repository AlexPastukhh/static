package structuralprobe;

import java.io.IOException;
import java.util.List;

public final class StructuralControlFixture {
    interface Gateway {
        String load(String value);
    }

    static boolean a(String value) {
        return value != null;
    }

    static boolean b(String value) {
        return value.length() > 1;
    }

    static boolean c(String value) {
        return value.startsWith("x");
    }

    static String nested(String value) {
        return value == null ? "" : value.trim();
    }

    public String exercise(List<String> items, int mode, Gateway gateway) {
        String value = nested(items.get(0));

        if (a(value) && (b(value) || c(value))) {
            value = nested(value);
        } else {
            value = nested("else");
        }

        switch (mode) {
            case 1:
                value = nested("one");
                break;
            case 2:
                return gateway.load(value);
            default:
                value = nested("default");
        }

        String selected = mode > 0 ? gateway.load(value) : nested(value);

        value = nested(value) + nested(value);

        for (int i = 0; i < items.size(); i++) {
            if (i == 1) {
                continue;
            }
            if (i > 3) {
                break;
            }
            value = nested(items.get(i));
        }

        for (String item : items) {
            value = nested(item);
        }

        while (a(value)) {
            value = nested(value);
            break;
        }

        try {
            if (selected == null) {
                throw new IOException("selected");
            }
            value = gateway.load(selected);
        } catch (IOException error) {
            value = nested(error.getMessage());
        } finally {
            nested("finally");
        }

        if (value.isEmpty()) {
            return "empty";
        }

        return value;
    }
}
