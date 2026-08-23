from main import app as application

if __name__ == '__main__':
    import uvicorn
    uvicorn.run(application, host='0.0.0.0', port=8000)
