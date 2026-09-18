-- ======================================================================
-- PREPARACIÓN DEL ENTORNO (Evita errores si el script se corre 2 veces)
-- ======================================================================
USE master;
GO

IF DB_ID('CrediCore') IS NOT NULL
BEGIN
    ALTER DATABASE CrediCore SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE CrediCore;
END
GO

-- 1. Creación de la Base de Datos
CREATE DATABASE CrediCore;
GO

USE CrediCore;
GO

-- ======================================================================
-- FASE 1: CREACIÓN DE ESQUEMAS, TABLAS Y RESTRICCIONES (DDL)
-- ======================================================================

-- Creación de Esquemas Lógicos para seguridad
CREATE SCHEMA Operaciones;
GO
CREATE SCHEMA Garantias;
GO

-- Tabla Clientes con restricción UNIQUE para DPI
CREATE TABLE Operaciones.Clientes (
    IdCliente INT IDENTITY(1,1) PRIMARY KEY,
    Nombres VARCHAR(100) NOT NULL,
    Apellidos VARCHAR(100) NOT NULL,
    DPI VARCHAR(13) NOT NULL UNIQUE, -- Restricción: DPI no se puede repetir
    Telefono VARCHAR(15),
    Correo VARCHAR(100)
);
GO

-- Tabla Vehiculos con reglas de negocio (CHECK) y UNIQUE
CREATE TABLE Garantias.Vehiculos (
    IdVehiculo INT IDENTITY(1,1) PRIMARY KEY,
    Marca VARCHAR(50) NOT NULL,
    Modelo VARCHAR(50) NOT NULL,
    Año INT NOT NULL CHECK (Año >= 2011), -- Restricción: Vehículos del 2011 en adelante
    Color VARCHAR(30),
    NumeroTitulo VARCHAR(50) NOT NULL,
    Placa VARCHAR(10) NOT NULL UNIQUE, -- Restricción: Placa no se puede repetir
    Chasis VARCHAR(50) NOT NULL UNIQUE -- Restricción: Chasis no se puede repetir
);
GO

-- Tabla Creditos con reglas de negocio financieras
CREATE TABLE Operaciones.Creditos (
    IdCredito INT IDENTITY(1,1) PRIMARY KEY,
    IdCliente INT NOT NULL,
    IdVehiculo INT NOT NULL,
    Monto DECIMAL(18, 2) NOT NULL CHECK (Monto > 1000.00), -- Restricción: Monto mínimo Q1,000
    TasaInteres DECIMAL(5, 2) NOT NULL CHECK (TasaInteres >= 0.00), -- Restricción: Tasas positivas
    Estado VARCHAR(20) DEFAULT 'Activo',
    FechaDesembolso DATETIME DEFAULT GETDATE()
);
GO

-- ======================================================================
-- FASE 2: INSERCIÓN DE DATOS VÁLIDOS (DML)
-- ======================================================================

-- Inserción de 3 clientes válidos
INSERT INTO Operaciones.Clientes (Nombres, Apellidos, DPI, Telefono, Correo) VALUES
('Ana Lucía', 'Pérez Ruiz', '1234567890101', '5555-1234', 'ana.perez@email.com'),
('Carlos René', 'Gómez', '9876543210101', '4444-9876', 'carlos.g@email.com'),
('María Fernanda', 'López', '3333444455556', '3333-1111', 'mafer.lopez@email.com');
GO

-- Inserción de 3 vehículos válidos (Años 2015 a 2020)
INSERT INTO Garantias.Vehiculos (Marca, Modelo, Año, Color, NumeroTitulo, Placa, Chasis) VALUES
('Toyota', 'Hilux', 2018, 'Gris', 'TIT-999888', 'P-123ABC', 'CH-11111111'),
('Honda', 'Civic', 2015, 'Rojo', 'TIT-777666', 'P-987XYZ', 'CH-22222222'),
('Mazda', '3', 2020, 'Azul', 'TIT-555444', 'P-555DEF', 'CH-33333333');
GO

-- Inserción de créditos enlazando clientes y vehículos con montos válidos
INSERT INTO Operaciones.Creditos (IdCliente, IdVehiculo, Monto, TasaInteres) VALUES
(1, 1, 25000.00, 12.5),
(2, 2, 15000.00, 15.0),
(3, 3, 40000.00, 10.0);
GO

-- ======================================================================
-- FASE 3: PRUEBAS DE RESTRICCIONES
-- NOTA: Se dejan comentadas para cumplir el requisito de ejecución sin errores.
-- ======================================================================

/*
-- Prueba 1: Regla CHECK (Vehículo menor a 2011)
INSERT INTO Garantias.Vehiculos (Marca, Modelo, Año, Color, NumeroTitulo, Placa, Chasis)
VALUES ('Nissan', 'Sentra', 2005, 'Blanco', 'TIT-111222', 'P-999ZZZ', 'CH-99999999');
GO

-- Prueba 2: Regla CHECK (Monto menor a Q1,000)
INSERT INTO Operaciones.Creditos (IdCliente, IdVehiculo, Monto, TasaInteres)
VALUES (1, 1, 500.00, 10.0);
GO

-- Prueba 3: Regla UNIQUE (DPI duplicado)
INSERT INTO Operaciones.Clientes (Nombres, Apellidos, DPI, Telefono, Correo)
VALUES ('Pedro', 'Martinez', '1234567890101', '2222-3333', 'pedro@email.com');
GO
*/