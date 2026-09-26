from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
import subprocess
import sys


@dataclass(frozen=True)
class Order:
    id: str
    amount: float


class PaymentGateway(ABC):
    @abstractmethod
    def pay(self, order: Order) -> None:
        raise NotImplementedError


class CardGateway(PaymentGateway):
    def pay(self, order: Order) -> None:
        print(f"CardGateway.pay order={order.id} amount={order.amount:g}")


class BankGateway(PaymentGateway):
    def pay(self, order: Order) -> None:
        print(f"BankGateway.pay order={order.id} amount={order.amount:g}")


class PaymentGatewayFactory:
    @staticmethod
    def create(kind: str) -> PaymentGateway:
        return BankGateway() if kind == "bank" else CardGateway()


class AuditService:
    def flag_large_order(self, order: Order) -> None:
        print(f"AUDIT {order.id}")


class OrderRepository:
    def save(self, order: Order) -> None:
        print(f"OrderRepository.save {order.id}")


class OrderService:
    def __init__(
        self,
        gateway: PaymentGateway,
        audit: AuditService,
        repository: OrderRepository,
    ) -> None:
        self.gateway = gateway
        self.audit = audit
        self.repository = repository

    def place_order(self, order: Order) -> None:
        self.gateway.pay(order)

        if order.amount > 1000:
            self.audit.flag_large_order(order)

        self.repository.save(order)


class UnsafeCli:
    @staticmethod
    def run(user_input: str) -> None:
        # Deliberately unsafe and only reachable with --unsafe.
        subprocess.run(user_input, shell=True, check=False)


def main(argv: list[str] | None = None) -> None:
    args = list(sys.argv[1:] if argv is None else argv)

    if len(args) >= 2 and args[0] == "--unsafe":
        UnsafeCli.run(args[1])
        return

    gateway = PaymentGatewayFactory.create("card")
    service = OrderService(gateway, AuditService(), OrderRepository())
    order = Order("ORD-42", 125)

    service.place_order(order)
    print(f"DONE {order.id}")


if __name__ == "__main__":
    main()
