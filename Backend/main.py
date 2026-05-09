# from unittest import result
from fastapi import FastAPI, UploadFile, File, Form
import shutil
import sys
from PIL import Image
import cv2
from matplotlib import transforms
import torch
import os
import whisper
from ultralytics import YOLO
from ultralytics.engine.results import Results
sys.path.append('../CNNmodel')
sys.path.append('../YOLO')
sys.path.append('../TTS_STT')

 
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

model_stt = whisper.load_model("base")
cnn_model = torch.load("../CNNmodel/code/model.pt", map_location=device)
yolo_model = YOLO("YOLO\code\yolo11n.pt")
app = FastAPI()



cnn_model.to(device)
cnn_model.eval()

test_transform = transforms.Compose([
    transforms.Resize((224, 224)),
    transforms.ToTensor(),
    transforms.Normalize(mean=[0.5, 0.5, 0.5], std=[0.5, 0.5, 0.5]),
])

classes = ["SodaBottle", "WaterBottle"]

def HSV_predict(image_path):
    image = cv2.imread(image_path)
    hsv_img = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    colors = {
        "red" : ((0,100,50), (10,255,255)),
        "yellow" : ((20,100,100), (30,255,255)),
        "green" : ((40,50,50), (80,255,255)),
        "blue" : ((100,100,50), (130,255,255)),
    }
    for color, (lower, upper) in colors.items():
        mask = cv2.inRange(hsv_img, lower, upper)
        if cv2.countNonZero(mask) > 0:
            # couleur dominante détectée
            return color
    return "color non détecté"

@app.post("/listen")
async def listen(audio: UploadFile = File(...)):
    os.makedirs("../TTS_STT/audio", exist_ok=True)
    audio_path = "../TTS_STT/audio/audio.m4a"
    with open(audio_path, "wb") as f:
        shutil.copyfileobj(audio.file, f)
    
    text = model_stt.transcribe(audio_path)["text"]
    print(f"STT dit : {text}")
    CNN_lst= ["soda", "water", "soda or water", "soda and water"]
    HSV_lst = ["color","what color", "what is the color", "what's the color", "what is the color of this", "what's the color of this"]
    
    if any(item in text.lower() for item in CNN_lst):
        return {"model": "CNN"}
    elif any(item in text.lower() for item in HSV_lst):
        return {"model": "HSV"}
    else :
        return {"model": "YOLO"}
    



@app.post("/predict") 
async def predict(
    image: UploadFile = File(...),
    model: str = Form(...)  
):
    image_path = "received_image.jpg"
    with open(image_path, "wb") as f:
        shutil.copyfileobj(image.file, f)
    
    print(f"image reçue ")
    print(f"modèle reçu : {model}")

    if model == "CNN":
        image = Image.open(image_path).convert("RGB")  
        image = test_transform(image).unsqueeze(0).to(device)  # ✅ transform + batch + GPU
        with torch.no_grad():                          # ✅ pas de gradient
            outputs = cnn_model(image)
            _, predicted = torch.max(outputs, 1)
            rst = classes[predicted.item()]  
    elif model == "YOLO":  
        results = yolo_model.predict(image_path)
        rst = results[0].verbose()
    elif model == "HSV":
        rst = HSV_predict(image_path)
    return {"result" : rst}


