from airflow.decorators import dag, task
from datetime import datetime

@dag(
    dag_id="example_dag",
    start_date=datetime(2024, 1, 1),
    schedule=None,   # shows in UI even if None
    catchup=False,
)
def example():
    @task
    def hello():
        print("hi")
    hello()

example() 