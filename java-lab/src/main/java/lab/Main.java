package lab;

import java.io.IOException;

record Order(String id, double amount) {}

interface PaymentGateway {
    void pay(Order order);
}

final class CardGateway implements PaymentGateway {
    @Override
    public void pay(Order order) {
        System.out.printf("CardGateway.pay order=%s amount=%.0f%n", order.id(), order.amount());
    }
}

final class BankGateway implements PaymentGateway {
    @Override
    public void pay(Order order) {
        System.out.printf("BankGateway.pay order=%s amount=%.0f%n", order.id(), order.amount());
    }
}

final class PaymentGatewayFactory {
    static PaymentGateway create(String kind) {
        return "bank".equals(kind) ? new BankGateway() : new CardGateway();
    }
}

final class AuditService {
    void flagLargeOrder(Order order) {
        System.out.println("AUDIT " + order.id());
    }
}

final class OrderRepository {
    void save(Order order) {
        System.out.println("OrderRepository.save " + order.id());
    }
}

final class OrderService {
    private final PaymentGateway gateway;
    private final AuditService audit;
    private final OrderRepository repository;

    OrderService(PaymentGateway gateway, AuditService audit, OrderRepository repository) {
        this.gateway = gateway;
        this.audit = audit;
        this.repository = repository;
    }

    void placeOrder(Order order) {
        gateway.pay(order);

        if (order.amount() > 1000.0) {
            audit.flagLargeOrder(order);
        }

        repository.save(order);
    }
}

final class UnsafeCli {
    private UnsafeCli() {}

    // Deliberately unsafe and only reachable when the program is run with --unsafe.
    static void run(String userInput) throws IOException, InterruptedException {
        Process process = Runtime.getRuntime().exec(new String[]{"/bin/sh", "-c", userInput});
        process.waitFor();
    }
}

public final class Main {
    public static void main(String[] args) throws Exception {
        if (args.length >= 2 && "--unsafe".equals(args[0])) {
            UnsafeCli.run(args[1]);
            return;
        }

        PaymentGateway gateway = PaymentGatewayFactory.create("card");
        OrderService service =
            new OrderService(gateway, new AuditService(), new OrderRepository());
        Order order = new Order("ORD-42", 125.0);

        service.placeOrder(order);
        System.out.println("DONE " + order.id());
    }
}
