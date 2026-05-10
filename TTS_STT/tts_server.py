import torch
import soundfile as sf
from qwen_tts import Qwen3TTSModel
from fastapi import FastAPI
from fastapi.responses import FileResponse


app = FastAPI()
model = Qwen3TTSModel.from_pretrained(
    "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice",
    device_map="cuda:0",
    dtype=torch.bfloat16,
)

@app.post("/tts")
async def generate(text: str):
    wavs, sr = model.generate_custom_voice(
        text=text,
        voice="Chelsie",
        language="English",
        speaker="Aiden",
        instruction="Speak in a professional tone.",


    )
    sf.write("TTSaudio/output.wav", wavs[0], sr)
    return FileResponse("TTSaudio/output.wav", media_type="audio/wav")