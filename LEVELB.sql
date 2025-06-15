USE AdventureWorks2019;
GO

DROP PROCEDURE IF EXISTS InsertOrderDetails;
GO

CREATE PROCEDURE InsertOrderDetails
    @OrderID INT,
    @ProductID INT,
    @Quantity INT,
    @UnitPrice MONEY = NULL,
    @Discount FLOAT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActualUnitPrice MONEY;
    DECLARE @UnitsInStock INT;

   
    IF @UnitPrice IS NULL
    BEGIN
        SELECT @ActualUnitPrice = ListPrice
        FROM Production.Product
        WHERE ProductID = @ProductID;
    END
    ELSE
    BEGIN
        SET @ActualUnitPrice = @UnitPrice;
    END

    
    SELECT @UnitsInStock = Quantity
    FROM Production.ProductInventory
    WHERE ProductID = @ProductID;

    IF @UnitsInStock IS NULL
    BEGIN
        PRINT 'Product not found or no inventory record.';
        RETURN;
    END

    IF @UnitsInStock < @Quantity
    BEGIN
        PRINT 'Not enough stock available. Order aborted.';
        RETURN;
    END

    
    INSERT INTO dbo.OrderDetails (OrderID, ProductID, UnitPrice, Quantity, Discount)
    VALUES (@OrderID, @ProductID, @ActualUnitPrice, @Quantity, @Discount);

    IF @@ROWCOUNT = 0
    BEGIN
        PRINT 'Failed to place the order. Please try again.';
        RETURN;
    END

    
    UPDATE Production.ProductInventory
    SET Quantity = Quantity - @Quantity
    WHERE ProductID = @ProductID;

   
    IF (@UnitsInStock - @Quantity) < 10
    BEGIN
        PRINT 'Warning: Quantity in stock has dropped below threshold.';
    END

    PRINT 'Order placed successfully.';
END;
GO
SELECT TOP 10 ProductID, Quantity 
FROM Production.ProductInventory
WHERE Quantity > 0;
EXEC InsertOrderDetails 
    @OrderID = 1001, 
    @ProductID = 760, 
    @Quantity = 1;



DROP PROCEDURE IF EXISTS UpdateOrderDetails;
GO

CREATE PROCEDURE UpdateOrderDetails
    @OrderID INT,
    @ProductID INT,
    @UnitPrice MONEY = NULL,
    @Quantity SMALLINT = NULL,
    @Discount FLOAT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OldQty SMALLINT;

    
    IF @Quantity IS NOT NULL
    BEGIN
        SELECT @OldQty = OrderQty
        FROM Sales.SalesOrderDetail
        WHERE SalesOrderID = @OrderID AND ProductID = @ProductID;
    END

    
    UPDATE Sales.SalesOrderDetail
    SET 
        UnitPrice = ISNULL(@UnitPrice, UnitPrice),
        OrderQty = ISNULL(@Quantity, OrderQty),
        UnitPriceDiscount = ISNULL(@Discount, UnitPriceDiscount)
    WHERE SalesOrderID = @OrderID AND ProductID = @ProductID;

    
    IF @Quantity IS NOT NULL AND @OldQty IS NOT NULL
    BEGIN
        UPDATE Production.ProductInventory
        SET Quantity = Quantity + (@OldQty - @Quantity)
        WHERE ProductID = @ProductID;
    END
END;
GO


DROP PROCEDURE IF EXISTS GetOrderDetails;
GO

CREATE PROCEDURE GetOrderDetails
    @OrderID INT
AS
BEGIN
    SET NOCOUNT ON;

    
    IF NOT EXISTS (
        SELECT 1 
        FROM Sales.SalesOrderDetail 
        WHERE SalesOrderID = @OrderID
    )
    BEGIN
        PRINT 'The OrderID ' + CAST(@OrderID AS VARCHAR) + ' does not exist';
        RETURN 1;
    END

   
    SELECT * 
    FROM Sales.SalesOrderDetail 
    WHERE SalesOrderID = @OrderID;
END;
GO

DROP PROCEDURE IF EXISTS DeleteOrderDetails;
GO

CREATE PROCEDURE DeleteOrderDetails
    @OrderID INT,
    @ProductID INT
AS
BEGIN
    SET NOCOUNT ON;

   
    IF NOT EXISTS (
        SELECT 1 
        FROM Sales.SalesOrderDetail 
        WHERE SalesOrderID = @OrderID AND ProductID = @ProductID
    )
    BEGIN
        PRINT 'Invalid OrderID or ProductID. No such record exists.';
        RETURN -1;
    END

    
    DELETE FROM Sales.SalesOrderDetail
    WHERE SalesOrderID = @OrderID AND ProductID = @ProductID;

    PRINT 'Order detail deleted successfully.';
END;
GO




DROP FUNCTION IF EXISTS dbo.FormatDate_MMDDYYYY;
GO

CREATE FUNCTION dbo.FormatDate_MMDDYYYY
(
    @InputDate DATETIME
)
RETURNS VARCHAR(10)
AS
BEGIN
    DECLARE @FormattedDate VARCHAR(10);
    SET @FormattedDate = CONVERT(VARCHAR(10), @InputDate, 101);  -- 101 = MM/DD/YYYY
    RETURN @FormattedDate;
END;
GO
SELECT dbo.FormatDate_MMDDYYYY(GETDATE());

GO
DROP FUNCTION IF EXISTS dbo.FormatDate_YYYYMMDD;
GO

CREATE FUNCTION dbo.FormatDate_YYYYMMDD
(
    @InputDate DATETIME
)
RETURNS VARCHAR(8)
AS
BEGIN
    DECLARE @FormattedDate VARCHAR(8);
    SET @FormattedDate = CONVERT(VARCHAR(8), @InputDate, 112); -- 112 = YYYYMMDD
    RETURN @FormattedDate;
END;
GO


SELECT dbo.FormatDate_YYYYMMDD(GETDATE());




DROP VIEW IF EXISTS vwCustomerOrders;
GO

CREATE VIEW vwCustomerOrders AS
SELECT 
    s.Name AS CompanyName,
    soh.SalesOrderID AS OrderID,
    soh.OrderDate,
    p.ProductID,
    p.Name AS ProductName,
    sod.OrderQty AS Quantity,
    sod.UnitPrice,
    sod.OrderQty * sod.UnitPrice AS Total
FROM Sales.SalesOrderHeader soh
JOIN Sales.Customer c ON soh.CustomerID = c.CustomerID
LEFT JOIN Sales.Store s ON c.StoreID = s.BusinessEntityID
JOIN Sales.SalesOrderDetail sod ON soh.SalesOrderID = sod.SalesOrderID
JOIN Production.Product p ON sod.ProductID = p.ProductID;
GO

DROP VIEW IF EXISTS vwCustomerOrders_YesterdayOnly;
GO

CREATE VIEW vwCustomerOrders_YesterdayOnly AS
SELECT 
    s.Name AS CompanyName,
    soh.SalesOrderID AS OrderID,
    soh.OrderDate,
    p.ProductID,
    p.Name AS ProductName,
    sod.OrderQty AS Quantity,
    sod.UnitPrice,
    sod.OrderQty * sod.UnitPrice AS Total
FROM Sales.SalesOrderHeader soh
JOIN Sales.Customer c ON soh.CustomerID = c.CustomerID
LEFT JOIN Sales.Store s ON c.StoreID = s.BusinessEntityID
JOIN Sales.SalesOrderDetail sod ON soh.SalesOrderID = sod.SalesOrderID
JOIN Production.Product p ON sod.ProductID = p.ProductID
WHERE CAST(soh.OrderDate AS DATE) = CAST(DATEADD(DAY, -1, GETDATE()) AS DATE);
GO


USE AdventureWorks2019;
GO

IF OBJECT_ID('Sales.trg_DeleteOrder', 'TR') IS NOT NULL
    DROP TRIGGER Sales.trg_DeleteOrder;
GO

CREATE TRIGGER Sales.trg_DeleteOrder
ON Sales.SalesOrderHeader
INSTEAD OF DELETE
AS
BEGIN
    SET NOCOUNT ON;

    
    DELETE sod
    FROM Sales.SalesOrderDetail sod
    INNER JOIN deleted d ON sod.SalesOrderID = d.SalesOrderID;

    
    DELETE soh
    FROM Sales.SalesOrderHeader soh
    INNER JOIN deleted d ON soh.SalesOrderID = d.SalesOrderID;
END;
GO


USE AdventureWorks2019;
GO

IF OBJECT_ID('Sales.trg_InsertOrderDetail_CheckStock', 'TR') IS NOT NULL
    DROP TRIGGER Sales.trg_InsertOrderDetail_CheckStock;
GO

CREATE TRIGGER Sales.trg_InsertOrderDetail_CheckStock
ON Sales.SalesOrderDetail
INSTEAD OF INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @insufficientCount INT;

    
    SELECT @insufficientCount = COUNT(*)
    FROM inserted i
    JOIN Production.ProductInventory pi ON i.ProductID = pi.ProductID
    WHERE i.OrderQty > pi.Quantity;

    IF @insufficientCount > 0
    BEGIN
        RAISERROR('Insufficient stock to place this order.', 16, 1);
        ROLLBACK TRANSACTION;
        RETURN;
    END

    INSERT INTO Sales.SalesOrderDetail (SalesOrderID, ProductID, OrderQty, UnitPrice, UnitPriceDiscount, rowguid, ModifiedDate)
    SELECT 
        SalesOrderID, ProductID, OrderQty, UnitPrice, UnitPriceDiscount, NEWID(), GETDATE()
    FROM inserted;

    
    UPDATE pi
    SET pi.Quantity = pi.Quantity - i.OrderQty
    FROM Production.ProductInventory pi
    JOIN inserted i ON pi.ProductID = i.ProductID;
END;
GO

    







