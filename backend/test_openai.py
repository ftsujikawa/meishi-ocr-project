from openai import OpenAI

client = OpenAI()

res = client.chat.completions.create(
    model="gpt-4o-mini",
    messages=[
        {"role": "user", "content": "日本語で「APIテスト成功」と返してください"}
    ],
    temperature=0.0,
)

print(res.choices[0].message.content)
