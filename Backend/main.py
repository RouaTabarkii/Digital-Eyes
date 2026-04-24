from fastapi import FastAPI, UploadFile, File
from fastapi.responses import FileResponse

app = FastAPI()

@app.post("/listen")
async def listen(
    audio: UploadFile = File(...),
    video: UploadFile = File(...)
):
    

    
    # 1. STT ici
    # 2. Model 1 ou Model 2 ici
    # 3. TTS ici

    return FileResponse("response.mp3", media_type="audio/mpeg")