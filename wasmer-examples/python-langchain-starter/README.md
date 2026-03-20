# LangChain + Streamlit Chat + Wasmer

This example shows how to host a **Streamlit** chat UI backed by **LangChain** and OpenAI on **Wasmer Edge**.

## Demo

https://langchain-starter-template.wasmer.app/

## How it Works

`Home.py` renders the entire chat experience:

* The sidebar captures an OpenAI API key via `st.text_input(..., type="password")`.
* Chat history is stored in `st.session_state["messages"]` as LangChain `ChatMessage` objects so conversations persist across reruns.
* `StreamHandler`, a custom `BaseCallbackHandler`, streams tokens into the UI by updating a placeholder container.
* When a user submits a prompt, the app creates `ChatOpenAI(streaming=True, callbacks=[stream_handler])`, invokes it with the full conversation history, and appends the assistant reply back into session state.

Because Streamlit re-runs the script on every interaction, keeping everything in session state is critical.

## Running Locally

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
streamlit run Home.py
```

Open the local URL Streamlit prints, enter your OpenAI API key in the sidebar, and start chatting.

## Deploying to Wasmer (Overview)

1. Bundle `Home.py` and `requirements.txt` (or a `pyproject.toml`).
2. Configure the start command to run Streamlit, e.g. `streamlit run Home.py --server.port=$PORT --server.address=0.0.0.0`.
3. Deploy to Wasmer Edge, set your `OPENAI_API_KEY` secret (or continue using the sidebar prompt), and visit `https://<your-subdomain>.wasmer.app/`.

> ⚠️ Never commit real API keys—use Wasmer secrets or prompt users at runtime like this demo.
