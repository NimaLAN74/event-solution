from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.empty import EmptyOperator

with DAG(
    dag_id="hello_dag",
    start_date=datetime(2024, 1, 1),
    schedule=None,
    catchup=False,
    default_args={"retries": 0, "owner": "airflow"},
    tags=["test"],
) as dag:
    EmptyOperator(task_id="start")