import { exec } from "node:child_process";

class Order {
  constructor(
    public readonly id: string,
    public readonly amount: number,
  ) {}
}

interface PaymentGateway {
  pay(order: Order): void;
}

class CardGateway implements PaymentGateway {
  pay(order: Order): void {
    console.log(`CardGateway.pay order=${order.id} amount=${order.amount}`);
  }
}

class BankGateway implements PaymentGateway {
  pay(order: Order): void {
    console.log(`BankGateway.pay order=${order.id} amount=${order.amount}`);
  }
}

class PaymentGatewayFactory {
  static create(kind: string): PaymentGateway {
    return kind === "bank" ? new BankGateway() : new CardGateway();
  }
}

class AuditService {
  flagLargeOrder(order: Order): void {
    console.log(`AUDIT ${order.id}`);
  }
}

class OrderRepository {
  save(order: Order): void {
    console.log(`OrderRepository.save ${order.id}`);
  }
}

class OrderService {
  constructor(
    private readonly gateway: PaymentGateway,
    private readonly audit: AuditService,
    private readonly repository: OrderRepository,
  ) {}

  placeOrder(order: Order): void {
    this.gateway.pay(order);

    if (order.amount > 1000) {
      this.audit.flagLargeOrder(order);
    }

    this.repository.save(order);
  }
}

class UnsafeCli {
  static run(userInput: string): void {
    // Deliberately unsafe and only reachable with --unsafe.
    exec(userInput);
  }
}

function main(args: string[]): void {
  if (args.length >= 2 && args[0] === "--unsafe") {
    UnsafeCli.run(args[1]);
    return;
  }

  const gateway = PaymentGatewayFactory.create("card");
  const service = new OrderService(
    gateway,
    new AuditService(),
    new OrderRepository(),
  );
  const order = new Order("ORD-42", 125);

  service.placeOrder(order);
  console.log(`DONE ${order.id}`);
}

main(process.argv.slice(2));
