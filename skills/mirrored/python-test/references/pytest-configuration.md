# Pytest Configuration

## Overview

This document covers pytest configuration including `pytest.ini`/`pyproject.toml`, `conftest.py` fixtures, and parallel execution with pytest-xdist.

---

## Configuration File

### Using pyproject.toml (Recommended)

```toml
# pyproject.toml
[tool.pytest.ini_options]
minversion = "8.0"
testpaths = ["tests"]
python_files = ["test_*.py"]
python_classes = ["Test*"]
python_functions = ["test_*"]
addopts = [
    "-ra",                    # Show summary of all non-passing tests
    "--strict-markers",       # Fail on unknown markers
    "--strict-config",        # Fail on config errors
    "-v",                     # Verbose output
]
markers = [
    "unit: Unit tests (fast, isolated)",
    "integration: Integration tests",
    "slow: Slow tests",
]
asyncio_mode = "auto"
filterwarnings = [
    "error",
    "ignore::DeprecationWarning",
]
```

### Using pytest.ini

```ini
# pytest.ini
[pytest]
minversion = 8.0
testpaths = tests
python_files = test_*.py
python_classes = Test*
python_functions = test_*
addopts = -ra --strict-markers --strict-config -v
markers =
    unit: Unit tests (fast, isolated)
    integration: Integration tests
    slow: Slow tests
asyncio_mode = auto
```

---

## Conftest.py Structure

### Root conftest.py

```python
# tests/conftest.py
import pytest
from unittest.mock import Mock

# --- Shared Fixtures ---

@pytest.fixture
def sample_book():
    """Create a sample book for testing."""
    from app.domain.entities.book import Book
    return Book(
        id="test-book-123",
        title="Test Book",
        author="Test Author",
        isbn="123-456-789",
        available=True,
        borrower_id=None,
        revision_id=1,
    )

# --- Markers ---

def pytest_configure(config):
    """Register custom markers."""
    config.addinivalue_line("markers", "unit: Unit tests")
    config.addinivalue_line("markers", "integration: Integration tests")
    config.addinivalue_line("markers", "slow: Slow tests")
```

### Unit Tests conftest.py

```python
# tests/units/conftest.py
import pytest
from unittest.mock import Mock

from app.usecases.borrowers.borrow_book import BookRepositoryInterface

@pytest.fixture
def mock_book_repository() -> Mock:
    """Create a mock book repository."""
    return Mock(spec=BookRepositoryInterface)
```

### Integration Tests conftest.py

```python
# tests/integrations/conftest.py
import pytest
from testcontainers.postgres import PostgresContainer
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

@pytest.fixture(scope="session")
def postgres_container():
    """PostgreSQL container for integration tests."""
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres

@pytest.fixture(scope="session")
def engine(postgres_container):
    """SQLAlchemy engine connected to test container."""
    from app.persistence.models import Base
    
    engine = create_engine(postgres_container.get_connection_url())
    Base.metadata.create_all(engine)
    yield engine
    Base.metadata.drop_all(engine)

@pytest.fixture
def db_session(engine):
    """Database session with automatic rollback."""
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()
    yield session
    session.rollback()
    session.close()
```

---

## Fixture Factories

For creating multiple similar test objects:

```python
# tests/fixtures/book_fixtures.py
import pytest
from typing import Callable
from app.domain.entities.book import Book

@pytest.fixture
def book_factory() -> Callable[..., Book]:
    """Factory for creating books with custom attributes."""
    def _create_book(
        id: str = "book-123",
        title: str = "Default Title",
        author: str = "Default Author",
        isbn: str = "000-000-000",
        available: bool = True,
        borrower_id: str | None = None,
        revision_id: int = 1,
    ) -> Book:
        return Book(
            id=id,
            title=title,
            author=author,
            isbn=isbn,
            available=available,
            borrower_id=borrower_id,
            revision_id=revision_id,
        )
    return _create_book

# Usage in tests:
def test_with_factory(book_factory):
    available_book = book_factory(available=True)
    borrowed_book = book_factory(available=False, borrower_id="user-1")
```

---

## Parallel Execution with pytest-xdist

### Installation

```bash
poetry add --group dev pytest-xdist
```

### Running Tests in Parallel

```bash
# Auto-detect CPU count
pytest -n auto

# Specific number of workers
pytest -n 4

# Distribute by file (faster for I/O-bound tests)
pytest -n auto --dist loadfile

# Distribute by test (better load balancing)
pytest -n auto --dist loadscope
```

### Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
addopts = [
    "-n", "auto",             # Parallel execution
    "--dist", "loadscope",    # Distribution strategy
]
```

### Worker-Isolated Fixtures

For fixtures that need to be unique per worker:

```python
@pytest.fixture(scope="session")
def worker_id(request):
    """Get unique worker ID for parallel execution."""
    if hasattr(request.config, "workerinput"):
        return request.config.workerinput["workerid"]
    return "master"

@pytest.fixture(scope="session")
def postgres_container(worker_id):
    """Unique container per worker."""
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield postgres
```

---

## Code Coverage

### Installation

```bash
poetry add --group dev pytest-cov
```

### Running with Coverage

```bash
# HTML report
pytest --cov=app --cov-report=html

# Terminal report
pytest --cov=app --cov-report=term-missing

# XML for CI
pytest --cov=app --cov-report=xml

# Fail if coverage below threshold
pytest --cov=app --cov-fail-under=80
```

### Configuration

```toml
# pyproject.toml
[tool.coverage.run]
source = ["app"]
branch = true
omit = [
    "*/tests/*",
    "*/__init__.py",
]

[tool.coverage.report]
exclude_lines = [
    "pragma: no cover",
    "if TYPE_CHECKING:",
    "raise NotImplementedError",
]
fail_under = 80
```

---

## Async Testing

### Installation

```bash
poetry add --group dev pytest-asyncio
```

### Configuration

```toml
# pyproject.toml
[tool.pytest.ini_options]
asyncio_mode = "auto"
```

### Usage

```python
import pytest

@pytest.mark.asyncio
async def test_async_function():
    result = await some_async_function()
    assert result == expected

# With auto mode, no marker needed:
async def test_async_auto():
    result = await some_async_function()
    assert result == expected
```

---

## Common Commands

```bash
# Run all tests
pytest

# Run unit tests only
pytest tests/units/

# Run with specific marker
pytest -m unit
pytest -m "not slow"

# Run failed tests from last run
pytest --lf

# Stop on first failure
pytest -x

# Show local variables in tracebacks
pytest -l

# Run tests matching pattern
pytest -k "borrow"

# Verbose with captured output
pytest -v -s

# Generate JUnit XML (for CI)
pytest --junitxml=report.xml
```
