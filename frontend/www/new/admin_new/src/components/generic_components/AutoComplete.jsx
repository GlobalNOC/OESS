import React, { useEffect, useState } from 'react';
import Autosuggest from 'react-autosuggest';

import './AutoComplete.css';

// Component.props.value is say 3
// Component.props.suggestions are { name: 'foo', value: 3 }.

// TODO
//
// Take props:
// - filterFunc
//
// Option must be selected from dropdown. If a valid entry is typed in, select
// the appropriate value and trigger the onChange callback.
//
// If an invalid entry is typed and the user tabs out either:
// 1. Reselect the last valid entry
// 2. Theme the input box in an error state

export const AutoComplete = (props) => {
    const [filteredSuggestions, setFilteredSuggestions] = useState([]);    
    const [input, setInput] = useState(''); // Text of input box

    useEffect(() => {
        for (let i=0; i < props.suggestions.length; i++) {
            if (props.suggestions[i].value == props.value) {
                setInput(props.suggestions[i].name);
            }
        }
    }, [props.suggestions]);

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
        console.log('suggestionselected', suggestion);
        try {
            props.onChange(suggestion.value);
        } catch(error) {
            console.error(error);
        }
    };

    const inputProps = {
        placeholder: props.placeholder,
        value:       input, // the text displayed in the input box
        // onBlur:      (e) => {
        //     // called when the input loses focus, e.g. when user presses Tab
        // },
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
