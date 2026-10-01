USE master;
GO

CREATE LOGIN AppCredicore WITH PASSWORD = 'Cr3diC0re#2026!';
GO

USE CrediCoreBD;
GO

CREATE USER AppCredicore FOR LOGIN AppCredicore;
GO

GRANT SELECT ON Operaciones10.vw_AtencionAlCliente TO AppCredicore;
GO

GRANT EXECUTE ON dbo.SP_ProcesarPago TO AppCredicore;
GO