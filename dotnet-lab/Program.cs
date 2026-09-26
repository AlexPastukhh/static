using System.Diagnostics;

namespace StaticLab;

public sealed record Order(string Id, decimal Amount);

public interface IPaymentGateway
{
    void Pay(Order order);
}

public sealed class CardGateway : IPaymentGateway
{
    public void Pay(Order order)
    {
        Console.WriteLine($"CardGateway.pay order={order.Id} amount={order.Amount}");
    }
}

public sealed class BankGateway : IPaymentGateway
{
    public void Pay(Order order)
    {
        Console.WriteLine($"BankGateway.pay order={order.Id} amount={order.Amount}");
    }
}

public static class PaymentGatewayFactory
{
    public static IPaymentGateway Create(string kind)
    {
        return kind == "bank" ? new BankGateway() : new CardGateway();
    }
}

public sealed class AuditService
{
    public void FlagLargeOrder(Order order)
    {
        Console.WriteLine($"AUDIT {order.Id}");
    }
}

public sealed class OrderRepository
{
    public void Save(Order order)
    {
        Console.WriteLine($"OrderRepository.save {order.Id}");
    }
}

public sealed class OrderService
{
    private readonly IPaymentGateway _gateway;
    private readonly AuditService _audit;
    private readonly OrderRepository _repository;

    public OrderService(IPaymentGateway gateway, AuditService audit, OrderRepository repository)
    {
        _gateway = gateway;
        _audit = audit;
        _repository = repository;
    }

    public void PlaceOrder(Order order)
    {
        _gateway.Pay(order);

        if (order.Amount > 1000m)
        {
            _audit.FlagLargeOrder(order);
        }

        _repository.Save(order);
    }
}

public static class UnsafeCli
{
    // Deliberately unsafe and only reachable when the program is run with --unsafe.
    public static void Run(string userInput)
    {
        var psi = new ProcessStartInfo
        {
            FileName = OperatingSystem.IsWindows() ? "cmd.exe" : "/bin/sh",
            UseShellExecute = false
        };

        if (OperatingSystem.IsWindows())
        {
            psi.ArgumentList.Add("/c");
        }
        else
        {
            psi.ArgumentList.Add("-c");
        }

        psi.ArgumentList.Add(userInput);
        using var process = Process.Start(psi);
        process?.WaitForExit();
    }
}

public static class Program
{
    public static void Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "--unsafe")
        {
            UnsafeCli.Run(args[1]);
            return;
        }

        var gateway = PaymentGatewayFactory.Create("card");
        var service = new OrderService(gateway, new AuditService(), new OrderRepository());
        var order = new Order("ORD-42", 125m);

        service.PlaceOrder(order);
        Console.WriteLine($"DONE {order.Id}");
    }
}
