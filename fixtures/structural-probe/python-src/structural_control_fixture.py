class Gateway:
    def load(self, value: str) -> str:
        return value


def a(value: str | None) -> bool:
    return value is not None


def b(value: str) -> bool:
    return len(value) > 1


def c(value: str) -> bool:
    return value.startswith("x")


def nested(value: str | None) -> str:
    return "" if value is None else value.strip()


def exercise_structural_probe(items: list[str], mode: int, gateway: Gateway) -> str:
    value = nested(items[0])

    if a(value) and (b(value) or c(value)):
        value = nested(value)
    else:
        value = nested("else")

    match mode:
        case 1:
            value = nested("one")
        case 2:
            return gateway.load(value)
        case _:
            value = nested("default")

    selected = gateway.load(value) if mode > 0 else nested(value)

    value = nested(value) + nested(value)

    for i, item in enumerate(items):
        if i == 1:
            continue
        if i > 3:
            break
        value = nested(item)

    while a(value):
        value = nested(value)
        break

    try:
        if selected is None:
            raise ValueError("selected")
        value = gateway.load(selected)
    except ValueError as error:
        value = nested(str(error))
    finally:
        nested("finally")

    if not value:
        return "empty"

    return value
