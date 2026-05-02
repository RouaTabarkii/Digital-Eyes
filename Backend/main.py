from fastapi import FastAPI, UploadFile, File
from fastapi.responses import FileResponse

app = FastAPI()

@app.post("/listen")
async def listen(
    audio: UploadFile = File(...),
    video: UploadFile = File(...)
):
    


    
    return FileResponse("response.mp3", media_type="audio/mpeg")