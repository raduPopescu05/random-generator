export function generateRandomNumber(){
    return Math.floor(Math.random() * 100)
}


export function generateRandomLetter(){
    return String.fromCharCode(65 + Math.floor(Math.random() * 26))
}


export function generateRandomRockPaperScissors(){
    const options = ['rocks', 'papers', 'scissor'];
    return options[Math.floor(Math.random() * 3)]
}