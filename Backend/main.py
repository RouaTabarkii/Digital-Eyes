from fastapi import FastAPI

app = FastAPI()

@app.get("/DigitalEyes") 
def root() :
        return {""}

@app.post("/DigitalEyes")
def root() :
    return {"message": "Hello World"}

@app.get("/DigitalEyes/{id}")
def root(id: int) :
    return {"message": f"Hello World {id}"}