/* ============================================================
   PROYECTO: ERP CrediCore - FASE 4 (Programabilidad y Auditoría)
   BASE: CrediCoreBD | ESQUEMAS: Operaciones10, Garantias10, Auditoria10
   MOTOR: SQL Server (T-SQL)
   ============================================================ */

USE CrediCoreBD;
GO


/* ============================================================
   PASO 0 (PREREQUISITO): Columna SaldoActual
   Hasta ahora Creditos solo tenía MontoCapital (el monto
   ORIGINAL otorgado, que nunca debe cambiar). Para poder
   procesar pagos necesitamos un saldo que sí disminuya.
   ============================================================ */

-- 0.1 Agregar la columna (temporalmente nullable para poder poblarla)
ALTER TABLE Operaciones10.Creditos
ADD SaldoActual DECIMAL(18,2) NULL;
GO

-- 0.2 Inicializar: al día de hoy, el saldo pendiente = el capital
--     otorgado (nadie ha abonado nada todavía)
UPDATE Operaciones10.Creditos
SET SaldoActual = MontoCapital;
GO

-- 0.3 Ahora sí, forzar NOT NULL y agregar una regla de negocio:
--     el saldo nunca puede ser negativo
ALTER TABLE Operaciones10.Creditos
ALTER COLUMN SaldoActual DECIMAL(18,2) NOT NULL;
GO

ALTER TABLE Operaciones10.Creditos
ADD CONSTRAINT CK_Creditos_SaldoNoNegativo CHECK (SaldoActual >= 0);
GO


/* ============================================================
   PARTE A: LA CAPA DE ABSTRACCIÓN (VISTAS)
   ============================================================ */

CREATE VIEW Operaciones10.vw_AtencionAlCliente AS
SELECT
    cl.Nombres + ' ' + cl.Apellidos AS NombreCliente,
    c.IdCredito                     AS NumeroCredito,
    v.Marca                         AS MarcaVehiculo,
    c.Estado                        AS EstadoCredito,
    c.SaldoActual                   AS SaldoActual
FROM Operaciones10.Creditos c
INNER JOIN Operaciones10.Clientes cl ON cl.IdCliente = c.IdCliente
INNER JOIN Garantias10.Vehiculos  v  ON v.IdVehiculo = c.IdVehiculo;
GO

-- Prueba: el asterisco NO debe mostrar DPI, telefono, ni chasis
SELECT * FROM Operaciones10.vw_AtencionAlCliente;
GO


/* ============================================================
   PARTE B: LÓGICA DE NEGOCIO SEGURA (PROCEDIMIENTOS ALMACENADOS)
   ============================================================ */

-- ------------------------------------------------------------
-- B.0 Tabla nueva requerida: HistorialPagos
-- ------------------------------------------------------------
CREATE TABLE Operaciones10.HistorialPagos (
    IdPago      INT IDENTITY(1,1) NOT NULL,
    IdCredito   INT                NOT NULL,
    MontoAbono  DECIMAL(18,2)      NOT NULL,
    FechaPago   DATETIME           NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_HistorialPagos PRIMARY KEY (IdPago),
    CONSTRAINT FK_HistorialPagos_Creditos FOREIGN KEY (IdCredito)
        REFERENCES Operaciones10.Creditos (IdCredito),
    CONSTRAINT CK_HistorialPagos_MontoPositivo CHECK (MontoAbono > 0)
);
GO

-- ------------------------------------------------------------
-- B.1 El Motor de Pagos: SP_ProcesarPago
-- ------------------------------------------------------------
CREATE PROCEDURE dbo.SP_ProcesarPago
    @IdCredito   INT,
    @MontoAbono  DECIMAL(18,2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SaldoActual DECIMAL(18,2);

    BEGIN TRY
        BEGIN TRAN;

            -- Leer el saldo actual del crédito (con bloqueo para evitar
            -- condiciones de carrera si dos pagos llegan al mismo tiempo)
            SELECT @SaldoActual = SaldoActual
            FROM Operaciones10.Creditos WITH (UPDLOCK, ROWLOCK)
            WHERE IdCredito = @IdCredito;

            -- Validación: ¿existe el crédito?
            IF @SaldoActual IS NULL
            BEGIN
                THROW 50001, 'El crédito indicado no existe.', 1;
            END

            -- Validación de negocio: no se puede abonar más de lo que se debe
            IF @MontoAbono > @SaldoActual
            BEGIN
                THROW 50002, 'El monto del abono supera el saldo actual del crédito.', 1;
            END

            -- 1. Registrar el pago en el historial
            INSERT INTO Operaciones10.HistorialPagos (IdCredito, MontoAbono)
            VALUES (@IdCredito, @MontoAbono);

            -- 2. Actualizar el saldo del crédito
            UPDATE Operaciones10.Creditos
            SET SaldoActual = SaldoActual - @MontoAbono
            WHERE IdCredito = @IdCredito;

        COMMIT TRAN;

        SELECT 'Pago procesado exitosamente.' AS Resultado,
               @IdCredito AS IdCredito,
               @MontoAbono AS MontoAbonado;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;

        -- Re-lanzar el error para que quien llamó al SP lo vea
        THROW;
    END CATCH
END;
GO


-- ------------------------------------------------------------
-- B.2 PRUEBAS DEL PROCEDIMIENTO
-- ------------------------------------------------------------

-- Elige un crédito real para probar
SELECT TOP 1 IdCredito, SaldoActual FROM Operaciones10.Creditos ORDER BY IdCredito;
GO

-- PRUEBA 1 (debe tener ÉXITO): abono pequeño y válido
-- Sustituye el 1 por un IdCredito real que exista en tu base
EXEC dbo.SP_ProcesarPago @IdCredito = 1, @MontoAbono = 100.00;
GO

-- Verifica que el saldo bajó
SELECT IdCredito, MontoCapital, SaldoActual FROM Operaciones10.Creditos WHERE IdCredito = 1;
GO

-- PRUEBA 2 (debe FALLAR a propósito): abono mayor al saldo
-- Esto debe disparar el THROW, el ROLLBACK, y no debe cambiar nada
EXEC dbo.SP_ProcesarPago @IdCredito = 1, @MontoAbono = 999999999.00;
GO


/* ============================================================
   PARTE C: EL AUDITOR SILENCIOSO (TRIGGERS)
   ============================================================ */

-- ------------------------------------------------------------
-- C.1 Esquema y tabla de bitácora
-- ------------------------------------------------------------
CREATE SCHEMA Auditoria10;
GO

CREATE TABLE Auditoria10.Logs_Creditos (
    IdLog          INT IDENTITY(1,1) NOT NULL,
    Accion         VARCHAR(100)      NOT NULL,
    ValorAnterior  DECIMAL(18,2)     NULL,
    ValorNuevo     DECIMAL(18,2)     NULL,
    FechaHora      DATETIME          NOT NULL DEFAULT GETDATE(),

    CONSTRAINT PK_Logs_Creditos PRIMARY KEY (IdLog)
);
GO

-- ------------------------------------------------------------
-- C.2 El Trigger: vigila cambios en TasaInteresMensual
-- Se dispara en CUALQUIER UPDATE a Creditos, pero solo registra
-- si la columna vigilada realmente cambió de valor.
-- ------------------------------------------------------------
CREATE TRIGGER Operaciones10.TR_Creditos_AuditarTasa
ON Operaciones10.Creditos
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- UPDATE(columna) es TRUE si esa columna vino en el SET del UPDATE
    IF UPDATE(TasaInteresMensual)
    BEGIN
        INSERT INTO Auditoria10.Logs_Creditos (Accion, ValorAnterior, ValorNuevo, FechaHora)
        SELECT
            'Cambio de Tasa de Interés - Credito #' + CAST(d.IdCredito AS VARCHAR(10)),
            d.TasaInteresMensual,   -- valor ANTES del cambio (tabla deleted)
            i.TasaInteresMensual,   -- valor DESPUÉS del cambio (tabla inserted)
            GETDATE()
        FROM deleted d
        INNER JOIN inserted i ON i.IdCredito = d.IdCredito
        WHERE d.TasaInteresMensual <> i.TasaInteresMensual;  -- solo si de verdad cambió
    END
END;
GO


-- ------------------------------------------------------------
-- C.3 PRUEBA DEL TRIGGER (simulación de manipulación sospechosa)
-- ------------------------------------------------------------

-- Ver la tasa actual de un crédito antes del "ataque"
SELECT IdCredito, TasaInteresMensual FROM Operaciones10.Creditos WHERE IdCredito = 2;
GO

-- Simular que alguien intenta bajar la tasa manualmente (sospechoso)
UPDATE Operaciones10.Creditos
SET TasaInteresMensual = 0.01
WHERE IdCredito = 2;
GO

-- Verificar que el Trigger SÍ lo capturó en la bitácora
SELECT * FROM Auditoria10.Logs_Creditos ORDER BY FechaHora DESC;
GO