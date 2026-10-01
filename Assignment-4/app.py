import os
from contextlib import asynccontextmanager
from pathlib import Path

import torch
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ConfigDict, Field, field_validator

from course_ner import CourseExtractor


class CourseRequest(BaseModel):
    model_config = ConfigDict(strict=True)
    text: str = Field(min_length=1, max_length=4000)

    @field_validator("text")
    @classmethod
    def require_text(cls, text):
        if not text.strip():
            raise ValueError("text must contain non-whitespace characters")
        return text


class CourseResponse(BaseModel):
    extracted_course_names: list[str]


def create_app(extractor=None):
    @asynccontextmanager
    async def lifespan(application):
        torch.set_num_threads(int(os.getenv("TORCH_NUM_THREADS", "2")))
        model_dir = os.getenv("MODEL_DIR", str(Path(__file__).parent / "model" / "course-ner"))
        application.state.extractor = extractor or CourseExtractor(model_dir)
        yield

    application = FastAPI(title="Course Name Extraction", lifespan=lifespan)

    @application.get("/health")
    def health():
        return {"status": "healthy", "model_loaded": True}

    @application.post("/extract-course-name/", response_model=CourseResponse)
    def extract_course_name(request: CourseRequest):
        try:
            names = application.state.extractor.extract(request.text)
        except ValueError as error:
            raise HTTPException(status_code=422, detail=str(error)) from error
        return CourseResponse(extracted_course_names=names)

    return application


app = create_app()
