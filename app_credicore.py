import streamlit as st
import pandas as pd
import pyodbc

# 1. Configuración de Conexión
# IMPORTANTE: usa la IP real de tu VM Ubuntu (la misma de DBeaver)
SERVER = '192.168.56.101'
DATABASE = 'CrediCoreBD'          # <- nombre REAL de la base
USERNAME = 'AppCredicore'         # <- usuario de mínimo privilegio (NUNCA sa)
PASSWORD = 'Cr3diC0re#2026!'      # <- la misma que pusiste en el script SQL

conn_str = (
    f'DRIVER={{ODBC Driver 17 for SQL Server}};'
    f'SERVER={SERVER};DATABASE={DATABASE};UID={USERNAME};PWD={PASSWORD}'
)

st.set_page_config(page_title="ERP CrediCore", layout="centered")
st.title("🏦 CrediCore - Módulo de Caja")
st.markdown("Interfaz conectada directamente al motor transaccional de SQL Server")

# 2. Leer la Vista Segura
st.subheader("Estado de Cuenta (Vista Segura)")
conn = None
try:
    conn = pyodbc.connect(conn_str)
    # Llamamos a la vista con su esquema completo, nunca a las tablas base
    query = "SELECT * FROM Operaciones10.vw_AtencionAlCliente"
    df = pd.read_sql(query, conn)
    st.dataframe(df, use_container_width=True)
except Exception as e:
    st.error(f"Error de conexión a la BD: {e}")

st.divider()

# 3. Formulario para ejecutar el Procedimiento Almacenado
st.subheader("Procesar Pago de Cuota")
with st.form("form_pago", clear_on_submit=False):
    id_credito = st.number_input("Número de Crédito (ID)", min_value=1, step=1)
    monto_pago = st.number_input("Monto a Abonar (Q)", min_value=1.0, step=100.0)
    btn_pagar = st.form_submit_button("Ejecutar Transacción")

    if btn_pagar:
        try:
            if conn is None:
                conn = pyodbc.connect(conn_str)
            cursor = conn.cursor()
            # Invocamos el SP con su esquema completo (dbo)
            cursor.execute(
                "EXEC dbo.SP_ProcesarPago @IdCredito = ?, @MontoAbono = ?",
                id_credito, monto_pago,
            )
            conn.commit()
            st.success("¡Pago procesado con éxito en SQL Server!")
            # st.rerun() desactivado temporalmente para poder capturar el
            # mensaje de éxito en pantalla antes del refresco. Descoméntalo
            # cuando grabes el video final, para que la tabla sí se actualice
            # en vivo frente a la cámara.
        except Exception as e:
            # Aquí se captura el THROW programado en el TRY...CATCH de SQL
            st.error(f"Transacción Rechazada por el Motor: {e}")