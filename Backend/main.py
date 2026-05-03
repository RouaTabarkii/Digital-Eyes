from fastapi import FastAPI, UploadFile, File, Form
import shutil
import sys
import torch
sys.path.append('../CNNmodel')
sys.path.append('../YOLO')
import os
import whisper
from ultralytics import YOLO


model_stt = whisper.load_model("base")
cnn_model = torch.load("../CNNmodel/code/model.pth")
yolo_model = YOLO("YOLO\code\yolo11n.pt")

app = FastAPI()

@app.post("/listen")
async def listen(audio: UploadFile = File(...)):
    os.makedirs("../TTS_STT/audio", exist_ok=True)
    audio_path = "../TTS_STT/audio/audio.m4a"
    with open(audio_path, "wb") as f:
        shutil.copyfileobj(audio.file, f)
    
    text = model_stt.transcribe(audio_path)["text"]
    print(f"STT dit : {text}")
    lst = ["soda", "water", "soda or water", "soda and water"]
    
    if any(item in text.lower() for item in lst):
        return {"model": "CNN"}
    else:
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
        cnn_model.eval()
        with torch.no_grad():
            prediction = cnn_model(torch.tensor([image_path]))
    elif model == "YOLO":  
        yolo_model.predict(image_path)

    return {"status": "received"}