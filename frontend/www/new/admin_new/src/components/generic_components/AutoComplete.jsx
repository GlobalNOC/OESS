import React, { useState } from 'react';
import Autosuggest from 'react-autosuggest';

import './AutoComplete.css';

// TODO: Take props:
// - suggestions [{ name: 'name', value: 'value' }]
// - filterFunc
// - onChange to track state at level above
export const AutoComplete = (props) => {
    const [filteredSuggestions, setFilteredSuggestions] = useState([]);    
    const [input, setInput] = useState('');

    const onSuggestionsFetchRequestedHandler = (input) => {
        // input = { value: '', reason: '' }
        let result = props.suggestions.filter((suggestion) => {
            if ( (new RegExp(input.value, 'i').test(suggestion.name)) ) {
                return true;
            } else if ( (new RegExp(input.value, 'i').test(suggestion.value)) ) {
                return true;
            } else {
                return false;
            }
        });
        setFilteredSuggestions(result);
    };

    const onSuggestionsClearRequestedHandler = () => setFilteredSuggestions(props.suggestions);

    const getSuggestionValue = (suggestion) => suggestion.name;

    const renderSuggestion = (suggestion) => {
        return <div>{suggestion.name}</div>;
    };

    const onSuggestionSelected = (event, { suggestion, suggestionValue, suggestionIndex, sectionIndex, method }) => {
        try {
            props.onChange(suggestion.value);
        } catch(error) {
            console.error(error);
        }
    };


    const inputProps = {
        placeholder: props.placeholder,
        value:       input,
        onChange:    (e, {newValue}) => {
            setInput(newValue);
        }
    };
    return (
        <Autosuggest
            id={props.id}
            suggestions={filteredSuggestions}
            onSuggestionsFetchRequested={onSuggestionsFetchRequestedHandler}
            onSuggestionsClearRequested={onSuggestionsClearRequestedHandler}
            onSuggestionSelected={onSuggestionSelected}
            getSuggestionValue={getSuggestionValue}
            renderSuggestion={renderSuggestion}
            inputProps={inputProps} />
    );
};
