# AppStack Django (ready starter)

## Local run (Windows / Git Bash)
```bash
cd app
python -m venv venv
source venv/Scripts/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

Open: http://127.0.0.1:8000/

Health check: http://127.0.0.1:8000/healthz

## Production (Linux)
```bash
pip install -r requirements.txt
python manage.py migrate
python manage.py collectstatic --noinput
gunicorn config.wsgi:application -c gunicorn_conf.py
```
