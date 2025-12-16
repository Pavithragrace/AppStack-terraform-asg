from django.http import JsonResponse, HttpResponse

def home(request):
    return HttpResponse("AppStack Django is running ✅")

def healthz(request):
    return JsonResponse({"status": "ok"})
