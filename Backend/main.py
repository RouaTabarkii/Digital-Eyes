from fastapi import FastAPI

app = FastAPI()

@app.get("/DigitalEyes") 
def root() :
        return {""}

@app.post("/DigitalEyes")
def root() :
    return {"message": "Hello World"}
